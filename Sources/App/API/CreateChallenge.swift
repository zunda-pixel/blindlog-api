import Foundation
import Hummingbird
import OpenAPIRuntime
import Records
import Valkey
import WebAuthn

extension API {
  func createChallenge(
    _ input: Operations.CreateChallenge.Input
  ) async throws -> Operations.CreateChallenge.Output {
    // 1. Generate Challenge
    let userID = UserTokenContext.currentUserID

    if userID != nil {
      guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
        userTokenAccessCount < RateLimitContext.authenticationEndpointMaxCount
      else {
        throw HTTPError(.tooManyRequests)
      }
    } else {
      guard let ipAddressCount = RateLimitContext.ipAddressAccessCount,
        ipAddressCount < RateLimitContext.authenticationEndpointMaxCount
      else {
        throw HTTPError(.tooManyRequests)
      }
    }

    let challenge: [UInt8] =
      if let userID {
        // SignUp
        webAuthn.beginRegistration(
          user: .init(
            id: Array(Data(userID.uuidString.utf8)),
            name: userID.uuidString,
            displayName: userID.uuidString
          ),
          timeout: .seconds(5 * 60),
          attestation: .none,
          publicKeyCredentialParameters: .supported
        ).challenge
      } else {
        webAuthn.beginAuthentication(
          timeout: .seconds(60),
          allowCredentials: nil,
          userVerification: .preferred
        ).challenge
      }

    // 2. Save Challenge to DB with expired date
    do {
      let challenge = Challenge(
        challenge: Data(challenge),
        userID: userID,
        purpose: userID == nil ? .authentication : .registration
      )
      try await cache.set(
        ValkeyKey("challenge:\(challenge.challenge.base64EncodedString())"),
        value: try JSONEncoder().encode(challenge),
        expiration: .seconds(60 * 10)  // 10 minutes
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.challenge.cache_write_failed",
        "Failed to save challenge with expiration",
        metadata: AppLogMetadata.userID(userID).merging([
          "auth.purpose": .string(userID == nil ? "authentication" : "registration"),
          "cache.operation": .string("set"),
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(challenge))))
  }
}
