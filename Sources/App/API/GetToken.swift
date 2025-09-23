import Foundation
import Hummingbird
import PostgresNIO
import SQLKit
import WebAuthn

struct PasskeyCredential: Codable, PostgresDecodable {
  var user_id: UUID
  var public_key: Data
  var sign_count: Int
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
    guard case .json(let bodyData) = input.body else {
      throw HTTPError(.badRequest)
    }
    let data = try JSONEncoder().encode(bodyData)

    let credential = try JSONDecoder().decode(
      AuthenticationCredential.self,
      from: data
    )

    let passkeyCredential = try await getPasskeyCredential(
      credentialID: credential.id.asString()
    )

    guard let passkeyCredential else {
      throw HTTPError(.internalServerError)
    }

    let verifiedAuthentication = try webAuthn.finishAuthentication(
      credential: credential,
      expectedChallenge: bodyData.challenge.base64decoded(),
      credentialPublicKey: Array(passkeyCredential.public_key),
      credentialCurrentSignCount: UInt32(passkeyCredential.sign_count)
    )

    // Delete Challenge
    try await database.query(
      """
      DELETE FROM challenges
      WHERE challenge = \(Data(bodyData.challenge.base64decoded()))
      """
    )

    // Update Sign count
    try await database.query(
      """
      UPDATE passkey_credentials
      SET sign_count = \(Int(verifiedAuthentication.newSignCount))
      WHERE id = \(verifiedAuthentication.credentialID.asString())
      """
    )

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
