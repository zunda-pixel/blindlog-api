import Foundation
import Hummingbird
import OpenAPIRuntime
import Records
import Valkey
import WebAuthn

extension API {
  func createRegistrationChallenge(
    _ input: Operations.CreateRegistrationChallenge.Input
  ) async throws -> Operations.CreateRegistrationChallenge.Output {
    // 1. Registration challenges are always bound to an authenticated user.
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
      userTokenAccessCount < RateLimitContext.authenticationEndpointMaxCount
    else {
      throw HTTPError(.tooManyRequests)
    }

    // 2. Generate the challenge.
    let challenge = webAuthn.beginRegistration(
      user: .init(
        id: Array(Data(userID.uuidString.utf8)),
        name: userID.uuidString,
        displayName: userID.uuidString
      ),
      timeout: .seconds(5 * 60),
      attestation: .none,
      publicKeyCredentialParameters: .supported
    ).challenge

    // 3. Save the challenge with an expiration.
    do {
      try await storeChallenge(challenge, userID: userID, purpose: .registration)
    } catch {
      logChallengeWriteFailure(userID: userID, purpose: .registration, error: error)
      return .badRequest
    }

    return .ok(.init(body: .json(challenge.base64URLEncodedStringValue())))
  }

  func createAuthenticationChallenge(
    _ input: Operations.CreateAuthenticationChallenge.Input
  ) async throws -> Operations.CreateAuthenticationChallenge.Output {
    // 1. Authentication challenges are not bound to a user, so rate limit by IP.
    guard let ipAddressAccessCount = RateLimitContext.ipAddressAccessCount,
      ipAddressAccessCount < RateLimitContext.authenticationEndpointMaxCount
    else {
      throw HTTPError(.tooManyRequests)
    }

    // 2. Generate the challenge.
    let challenge = webAuthn.beginAuthentication(
      timeout: .seconds(60),
      allowCredentials: nil,
      userVerification: .preferred
    ).challenge

    // 3. Save the challenge with an expiration.
    do {
      try await storeChallenge(challenge, userID: nil, purpose: .authentication)
    } catch {
      logChallengeWriteFailure(userID: nil, purpose: .authentication, error: error)
      return .badRequest
    }

    return .ok(.init(body: .json(challenge.base64URLEncodedStringValue())))
  }

  private func storeChallenge(
    _ challenge: [UInt8],
    userID: UUID?,
    purpose: Challenge.Purpose
  ) async throws {
    let record = Challenge(
      challenge: Data(challenge),
      userID: userID,
      purpose: purpose
    )
    try await cache.set(
      ValkeyKey("challenge:\(record.challenge.base64EncodedString())"),
      value: try JSONEncoder().encode(record),
      expiration: .seconds(60 * 10)  // 10 minutes
    )
  }

  private func logChallengeWriteFailure(
    userID: UUID?,
    purpose: Challenge.Purpose,
    error: any Error
  ) {
    AppRequestContext.current?.logger.appError(
      eventName: "auth.challenge.cache_write_failed",
      "Failed to save challenge with expiration",
      metadata: AppLogMetadata.userID(userID).merging([
        "auth.purpose": .string(purpose.rawValue),
        "cache.operation": .string("set"),
      ]) { _, new in new },
      error: error
    )
  }
}
