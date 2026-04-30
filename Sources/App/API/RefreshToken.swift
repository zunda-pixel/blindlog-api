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
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.refresh_token.invalid_subject",
        "Invalid JWT subject"
      )
      return .unauthorized
    }
    // verify expiration is not over.
    guard payload.expiration.value > Date() else {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.refresh_token.expired",
        "Refresh token expired",
        metadata: AppLogMetadata.userID(userID)
      )
      return .unauthorized
    }

    guard payload.tokenType == .refreshToken else {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.refresh_token.invalid_type",
        "Token type is not refresh token",
        metadata: AppLogMetadata.userID(userID)
      )
      return .unauthorized
    }

    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(userID: userID)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.token.issue_failed",
        "Failed to issue tokens from refresh token",
        metadata: AppLogMetadata.userID(userID).merging([
          "auth.flow": .string("refresh_token")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }
    return .ok(.init(body: .json(userToken)))
  }
}
