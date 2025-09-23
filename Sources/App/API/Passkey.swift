import Foundation
import Hummingbird
import PostgresNIO
import SQLKit
import WebAuthn

enum ChallengePurpose: String, PostgresCodable {
  case registration
  case authentication
}

extension API {
  func addPasskey(
    _ input: Operations.addPasskey.Input
  ) async throws -> Operations.addPasskey.Output {
    guard let userID = BearerAuthenticateUser.current?.userID else {
      throw HTTPError(.unauthorized)
    }
    // 1. Parse request payload
    guard case .json(let body) = input.body else { throw HTTPError(.badRequest) }
    let bodyData = try JSONEncoder().encode(body)
    let registrationCredential = try JSONDecoder().decode(
      RegistrationCredential.self,
      from: bodyData
    )

    // 2. Verify and delete challenge atomically
    let row = try await database.query(
      """
        DELETE FROM challenges
        WHERE challenge = \(Data(input.query.challenge.data))
          AND user_id = \(userID)
          AND purpose = \(ChallengePurpose.registration)
          AND expired_date > CURRENT_TIMESTAMP
        RETURNING 1
      """
    ).collect().first

    guard row != nil else {
      throw HTTPError(.badRequest)
    }

    // 3. Validate WebAuthn registration data
    let credential = try await webAuthn.finishRegistration(
      challenge: Array(input.query.challenge.data),
      credentialCreationData: registrationCredential,
      confirmCredentialIDNotRegisteredYet: { credentialID in
        let row = try await database.query(
          """
            SELECT 1 FROM passkey_credentials
            WHERE id = \(credentialID)
          """
        ).collect().first
        return row == nil
      }
    )

    // 4. Persist credential metadata
    try await database.query(
      """
        INSERT INTO passkey_credentials (id, user_id, public_key, sign_count)
        VALUES(\(registrationCredential.id.asString()), \(userID), \(Data(credential.publicKey)), \(Int64(credential.signCount)))
      """
    )

    return .ok
  }
}
