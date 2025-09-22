import Foundation
import WebAuthn
import AuthenticationServices
import Hummingbird

extension API {
  func getPublicKey(credentialID: String) async throws -> Data? {
    let row = try await database.query(
      """
      
      """
    ).collect().first
    
    let challnge = try row?.decode(String.self)
    
    return challnge.flatMap { Data(base64Encoded: $0) }
  }
  
  func getToken(
    _ input: Operations.getToken.Input
  ) async throws -> Operations.getToken.Output {
    guard case .json(let bodyData) = input.body else {
      throw HTTPError(.badRequest)
    }
    
    guard let challenge = Data(base64Encoded: bodyData.challenge) else {
      throw HTTPError(.badRequest)
    }
    
    let data = try JSONEncoder().encode(bodyData)
    
    let credential = try JSONDecoder().decode(
      AuthenticationCredential.self,
      from: data
    )
    
    let publicKey = try await getPublicKey(
      credentialID: credential.id.asString()
    )
    
    guard let publicKey else {
      throw HTTPError(.internalServerError)
    }
    
    _ = try webAuthn.finishAuthentication(
      credential: credential,
      expectedChallenge: Array(challenge),
      credentialPublicKey: Array(publicKey),
      credentialCurrentSignCount: 123
    )
    
    return .ok(
      .init(
        body: .json(
          .init(
            id: "",
            token: "",
            refreshToken: ""
          )
        )
      )
    )
  }
}
