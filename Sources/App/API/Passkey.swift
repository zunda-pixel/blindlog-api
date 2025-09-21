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
        SELECT * FROM user_challenge
        WHERE user_id = \(userID)
          AND challenge = \(input.query.challenge)
          AND expired_date > CURRENT_TIMESTAMP
      """
    ).collect().first

    guard row != nil else {
      throw HTTPError(.badRequest)
    }

    // 2. Verify Client Credential Data and get public key
    guard case .json(let body) = input.body else { throw HTTPError(.badRequest) }
    let bodyData = try JSONEncoder().encode(body)
    let registrationCredential: RegistrationCredential = try JSONDecoder().decode(
      RegistrationCredential.self,
      from: bodyData
    )

    let credential = try await webAuthn.finishRegistration(
      challenge: Array(Data(base64Encoded: input.query.challenge)!),
      credentialCreationData: registrationCredential,
      confirmCredentialIDNotRegisteredYet: { id in
        let row = try await database.query(
          """
            SELECT * FROM passkey_credential
            WHERE id = \(registrationCredential.id.asString())
          """
        ).collect().first
        return row == nil
      }
    )

    // 3. Save PublicKey to DB
    try await database.query(
      """
        INSERT INTO passkey_public_credential (id, public_key)
        VALUES(\(credential.id), \(Data(credential.publicKey).base64EncodedString()))
      """
    )

    return .ok
  }
}
