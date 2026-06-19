import Foundation
import JWTKit

extension API {
  func generateUserToken(
    userID: UUID
  ) async throws -> Components.Schemas.UserToken {
    let issuedAt = Date()
    let tokenExpiredDate = Date(timeIntervalSinceNow: 1 * 60 * 60)  // 1 hour

    let tokenPayload = JWTPayloadData(
      tokenType: .token,
      id: .init(value: UUID().uuidString),
      issuer: .init(value: jwtConfiguration.issuer),
      audience: .init(value: [jwtConfiguration.audience]),
      issuedAt: .init(value: issuedAt),
      subject: .init(value: userID.uuidString),
      expiration: .init(value: tokenExpiredDate)
    )

    let refreshTokenExpiredDate = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60)  // 30 days

    let refreshTokenPayload = JWTPayloadData(
      tokenType: .refreshToken,
      id: .init(value: UUID().uuidString),
      issuer: .init(value: jwtConfiguration.issuer),
      audience: .init(value: [jwtConfiguration.audience]),
      issuedAt: .init(value: issuedAt),
      subject: .init(value: userID.uuidString),
      expiration: .init(value: refreshTokenExpiredDate)
    )

    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)

    return .init(
      userID: userID.uuidString,
      token: token,
      tokenExpiredDate: tokenExpiredDate.timeIntervalSinceReferenceDate,
      refreshToken: refreshToken,
      refreshTokenExpiredDate: refreshTokenExpiredDate.timeIntervalSinceReferenceDate
    )
  }
}
