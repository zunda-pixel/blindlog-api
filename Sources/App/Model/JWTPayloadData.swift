import JWTKit

struct JWTPayloadData: JWTPayload, Equatable {
  var subject: SubjectClaim
  var expiration: ExpirationClaim
  var tokenType: TokenType

  func verify(using algorithm: some JWTAlgorithm) async throws {
    try self.expiration.verifyNotExpired()
  }

  enum CodingKeys: String, CodingKey {
    case subject = "sub"
    case expiration = "exp"
    case tokenType
  }

  enum TokenType: String, Codable {
    case token
    case refreshToken
  }
}
