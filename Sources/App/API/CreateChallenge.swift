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

    if let userID {
      guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
        userTokenAccessCount < 30
      else {
        throw HTTPError(.tooManyRequests)
      }
    } else {
      guard let ipAddressCount = RateLimitContext.ipAddressAccessCount, ipAddressCount < 30 else {
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
          )
        ).challenge
      } else {
        // SignIn
        webAuthn.beginAuthentication().challenge
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
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to save challenge with expiration",
        metadata: [
          "challenge": .string(Data(challenge).base64EncodedString()),
          "userID": .string(userID?.uuidString ?? "nil"),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(challenge))))
  }
}
