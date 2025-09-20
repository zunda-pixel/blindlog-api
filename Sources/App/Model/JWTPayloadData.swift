import JWTKit

struct JWTPayloadData: JWTPayload, Equatable {
  var subject: SubjectClaim
  var expiration: ExpirationClaim
  var userName: String

  func verify(using algorithm: some JWTAlgorithm) async throws {
    try self.expiration.verifyNotExpired()
  }
  
  enum CodingKeys: String, CodingKey {
    case subject = "sub"
    case expiration = "exp"
    case userName = "name"
  }
}
