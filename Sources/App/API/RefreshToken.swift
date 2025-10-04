import Foundation
import Hummingbird
import JWTKit
import PostgresNIO
import SQLKit
import Valkey

extension API {
  func generateUserToken(
    userID: UUID
  ) async throws -> Components.Schemas.UserToken {
    let tokenExpiredDate = Date(timeIntervalSinceNow: 1 * 60 * 60)  // 1 hour

    let tokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: tokenExpiredDate),
      tokenType: .token
    )

    let refreshTokenExpiredDate = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)  // 1 year

    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: refreshTokenExpiredDate),
      tokenType: .refreshToken
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

  func refreshToken(
    _ input: Operations.RefreshToken.Input
  ) async throws -> Operations.RefreshToken.Output {
    guard case .json(let body) = input.body else {
      return .unauthorized(.init())
    }

    let payload = try await jwtKeyCollection.verify(body.refreshToken, as: JWTPayloadData.self)

    guard let userID = UUID(uuidString: payload.subject.value) else {
      BasicRequestContext.current?.logger.debug("Invalid JWT subject \(payload.subject.value)")
      return .unauthorized(.init())
    }
    // verify expiration is not over.
    guard payload.expiration.value > Date() else {
      BasicRequestContext.current?.logger.debug("Token expired")
      return .unauthorized(.init())
    }

    guard payload.tokenType == .refreshToken else {
      BasicRequestContext.current?.logger.debug("Token type is not refresh token")
      return .unauthorized(.init())
    }

    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(userID: userID)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to issue tokens from refresh token",
        metadata: [
          "userID": .string(userID.uuidString),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }
    return .ok(.init(body: .json(userToken)))
  }
}
