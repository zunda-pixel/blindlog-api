import Foundation
import Hummingbird
import PostgresNIO
import WebAuthn

struct PasskeyCredential: Codable, PostgresDecodable {
  var userID: UUID
  var publicKey: Data
}

extension API {
  fileprivate func getPasskeyCredential(credentialID: String) async throws -> PasskeyCredential? {
    let row = try await database.query(
      """
        SELECT user_id, public_key FROM passkey_credentials
        WHERE id = \(credentialID)
      """
    ).collect().first

    let credential = try row?.decode(PasskeyCredential.self)

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

    _ = try webAuthn.finishAuthentication(
      credential: credential,
      expectedChallenge: Array(bodyData.challenge.data),
      credentialPublicKey: Array(passkeyCredential.publicKey),
      credentialCurrentSignCount: 123
    )

    let (token, refreshToken) = try await generateUserToken(
      userID: passkeyCredential.userID
    )

    return .ok(
      .init(
        body: .json(
          .init(
            id: passkeyCredential.userID.uuidString,
            token: token,
            refreshToken: refreshToken
          )
        )
      )
    )
  }
}
