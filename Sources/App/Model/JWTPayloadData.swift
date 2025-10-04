import JWTKit

struct JWTPayloadData: JWTPayload, Equatable {
  var tokenType: TokenType
  var subject: SubjectClaim
  var expiration: ExpirationClaim

  func verify(using algorithm: some JWTAlgorithm) async throws {
    try self.expiration.verifyNotExpired()
  }

  enum CodingKeys: String, CodingKey {
    case tokenType
    case subject = "sub"
    case expiration = "exp"
  }

  enum TokenType: String, Codable {
    case token
    case refreshToken
  }
}
