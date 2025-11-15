import Foundation
import Hummingbird
import JWTKit
import PostgresNIO
import SQLKit
import Valkey

extension API {
  func refreshToken(
    _ input: Operations.RefreshToken.Input
  ) async throws -> Operations.RefreshToken.Output {
    guard case .json(let body) = input.body else {
      return .badRequest
    }

    let payload = try await jwtKeyCollection.verify(body.refreshToken, as: JWTPayloadData.self)

    guard let userID = UUID(uuidString: payload.subject.value) else {
      BasicRequestContext.current?.logger.debug("Invalid JWT subject \(payload.subject.value)")
      return .unauthorized
    }
    // verify expiration is not over.
    guard payload.expiration.value > Date() else {
      BasicRequestContext.current?.logger.debug("Token expired")
      return .unauthorized
    }

    guard payload.tokenType == .refreshToken else {
      BasicRequestContext.current?.logger.debug("Token type is not refresh token")
      return .unauthorized
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
      return .badRequest
    }
    return .ok(.init(body: .json(userToken)))
  }
}
