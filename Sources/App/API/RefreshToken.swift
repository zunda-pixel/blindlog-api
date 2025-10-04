import Foundation
import Hummingbird
import JWTKit
import PostgresNIO
import SQLKit
import Valkey

extension API {
  func generateUserToken(
    userID: UUID
  ) async throws -> (token: String, refreshToken: String) {
    let tokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)),  // 1 hour
      tokenType: .token
    )

    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)),  // 1 year
      tokenType: .refreshToken
    )

    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)

    return (token, refreshToken)
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

    let token: String
    let refreshToken: String
    do {
      (token, refreshToken) = try await generateUserToken(userID: userID)
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
    return .ok(
      .init(
        body: .json(
          .init(
            userID: userID.uuidString,
            token: token,
            refreshToken: refreshToken
          ))))
  }
}
