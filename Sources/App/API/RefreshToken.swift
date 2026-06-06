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

    let payload: JWTPayloadData
    do {
      payload = try await jwtKeyCollection.verify(body.refreshToken, as: JWTPayloadData.self)
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.refresh_token.verify_failed",
        "Couldn't verify refresh token",
        error: error
      )
      return .unauthorized
    }

    guard payload.issuer.value == jwtConfiguration.issuer else {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.refresh_token.invalid_issuer",
        "Refresh token issuer is not accepted"
      )
      return .unauthorized
    }
    do {
      try payload.audience.verifyIntendedAudience(includes: jwtConfiguration.audience)
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.refresh_token.invalid_audience",
        "Refresh token audience is not accepted",
        error: error
      )
      return .unauthorized
    }

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

    do {
      guard try await !isRefreshTokenRevoked(payload) else {
        AppRequestContext.current?.logger.appLog(
          level: .debug,
          eventName: "auth.refresh_token.revoked",
          "Refresh token has been revoked",
          metadata: AppLogMetadata.userID(userID)
        )
        return .unauthorized
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.refresh_token.revoke_status_read_failed",
        "Failed to read refresh token revoke status",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("exists")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
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

  func revokeToken(
    _ input: Operations.RevokeToken.Input
  ) async throws -> Operations.RevokeToken.Output {
    guard case .json(let body) = input.body else {
      return .badRequest
    }

    let payload: JWTPayloadData
    do {
      payload = try await jwtKeyCollection.verify(body.refreshToken, as: JWTPayloadData.self)
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.revoke_token.verify_failed",
        "Couldn't verify refresh token",
        error: error
      )
      return .unauthorized
    }

    guard let userID = UUID(uuidString: payload.subject.value) else {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.revoke_token.invalid_subject",
        "Invalid JWT subject"
      )
      return .unauthorized
    }
    guard payload.expiration.value > Date() else {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.revoke_token.expired",
        "Refresh token expired",
        metadata: AppLogMetadata.userID(userID)
      )
      return .unauthorized
    }
    guard payload.tokenType == .refreshToken else {
      AppRequestContext.current?.logger.appLog(
        level: .debug,
        eventName: "auth.revoke_token.invalid_type",
        "Token type is not refresh token",
        metadata: AppLogMetadata.userID(userID)
      )
      return .unauthorized
    }

    do {
      try await revokeRefreshToken(payload)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.revoke_token.cache_write_failed",
        "Failed to write revoked refresh token",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("set")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok(.init())
  }

  fileprivate func isRefreshTokenRevoked(_ payload: JWTPayloadData) async throws -> Bool {
    try await cache.exists(keys: [revokedRefreshTokenCacheKey(payload)]) > 0
  }

  fileprivate func revokeRefreshToken(_ payload: JWTPayloadData) async throws {
    let remainingLifetime = Int(payload.expiration.value.timeIntervalSinceNow.rounded(.up))
    guard remainingLifetime > 0 else { return }
    try await cache.set(
      revokedRefreshTokenCacheKey(payload),
      value: Data("1".utf8),
      expiration: .seconds(remainingLifetime)
    )
  }

  fileprivate func revokedRefreshTokenCacheKey(_ payload: JWTPayloadData) -> ValkeyKey {
    ValkeyKey("revoked_refresh_token:\(payload.id.value)")
  }
}
