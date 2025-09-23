import Foundation
import Hummingbird
import WebAuthn

extension API {
  func addPasskey(
    _ input: Operations.addPasskey.Input
  ) async throws -> Operations.addPasskey.Output {
    guard let userID = BearerAuthenticateUser.current?.userID else {
      throw HTTPError(.unauthorized)
    }
    // 1. Verify Challenge is valid.
    let row = try await database.query(
      """
        SELECT 1 FROM challenges
        WHERE challenge = \(Data(input.query.challenge.data))
          AND expired_date > CURRENT_TIMESTAMP
      """
    ).collect().first

    guard row != nil else {
      throw HTTPError(.badRequest)
    }

    // 2. Verify Client Credential Data and get public key
    guard case .json(let body) = input.body else { throw HTTPError(.badRequest) }
    let bodyData = try JSONEncoder().encode(body)
    let registrationCredential = try JSONDecoder().decode(
      RegistrationCredential.self,
      from: bodyData
    )

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

    // 3. Save PublicKey to DB
    try await database.query(
      """
        INSERT INTO passkey_credentials (id, user_id, public_key, sign_count)
        VALUES(\(registrationCredential.id.asString()), \(userID), \(Data(credential.publicKey)), \(Int(credential.signCount)))
      """
    )

    return .ok
  }
}
