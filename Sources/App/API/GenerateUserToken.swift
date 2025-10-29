import Foundation
import JWTKit

extension API {
  func generateUserToken(
    userID: UUID
  ) async throws -> Components.Schemas.UserToken {
    let tokenExpiredDate = Date(timeIntervalSinceNow: 1 * 60 * 60)  // 1 hour

    let tokenPayload = JWTPayloadData(
      tokenType: .token,
      subject: .init(value: userID.uuidString),
      expiration: .init(value: tokenExpiredDate),
    )

    let refreshTokenExpiredDate = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)  // 1 year

    let refreshTokenPayload = JWTPayloadData(
      tokenType: .refreshToken,
      subject: .init(value: userID.uuidString),
      expiration: .init(value: refreshTokenExpiredDate),
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
