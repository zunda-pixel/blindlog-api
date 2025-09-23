import Foundation
import Hummingbird
import PostgresNIO
import SQLKit
import WebAuthn

struct PasskeyCredential: Codable, PostgresDecodable {
  var user_id: UUID
  var public_key: Data
  var sign_count: Int64
}

extension API {
  fileprivate func getPasskeyCredential(credentialID: String) async throws -> PasskeyCredential? {
    let row = try await database.query(
      """
        SELECT user_id, public_key, sign_count FROM passkey_credentials
        WHERE id = \(credentialID)
      """
    ).collect().first

    let credential = try row?.sql().decode(
      model: PasskeyCredential.self,
      with: SQLRowDecoder()
    )

    return credential
  }

  func createToken(
    _ input: Operations.createToken.Input
  ) async throws -> Operations.createToken.Output {
    // 1. Decode Data
    guard case .json(let bodyData) = input.body else {
      throw HTTPError(.badRequest)
    }

    let data = try JSONEncoder().encode(bodyData)

    let credential = try JSONDecoder().decode(
      AuthenticationCredential.self,
      from: data
    )

    // 2. Verify and delete challenge atomically.
    let row = try await database.query(
      """
        DELETE FROM challenges
        WHERE challenge = \(Data(bodyData.challenge.base64decoded()))
          AND user_id = \(PostgresData.null.value)
          AND purpose = \(ChallengePurpose.authentication)
          AND expired_date > CURRENT_TIMESTAMP
        RETURNING 1
      """
    ).collect().first

    guard row != nil else {
      throw HTTPError(.badRequest)
    }

    // 3. Get Passkey from DB
    let passkeyCredential = try await getPasskeyCredential(
      credentialID: credential.id.asString()
    )

    guard let passkeyCredential else {
      throw HTTPError(.internalServerError)
    }

    // 4. Verify Public Key
    let verifiedAuthentication = try webAuthn.finishAuthentication(
      credential: credential,
      expectedChallenge: bodyData.challenge.base64decoded(),
      credentialPublicKey: Array(passkeyCredential.public_key),
      credentialCurrentSignCount: UInt32(passkeyCredential.sign_count)
    )

    // 5. Update Sign count
    try await database.query(
      """
      UPDATE passkey_credentials
      SET sign_count = GREATEST(sign_count, \(Int64(verifiedAuthentication.newSignCount)))
      WHERE id = \(verifiedAuthentication.credentialID.asString())
      """
    )

    // 6. Generate User Token
    let (token, refreshToken) = try await generateUserToken(
      userID: passkeyCredential.user_id
    )

    return .ok(
      .init(
        body: .json(
          .init(
            id: passkeyCredential.user_id.uuidString,
            token: token,
            refreshToken: refreshToken
          )
        )
      )
    )
  }
}
