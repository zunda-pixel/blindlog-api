import ExtrasBase64
import Foundation
import Hummingbird
import Logging
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey
import WebAuthn

extension API {
  func createTokenFromPasskey(
    _ input: Operations.CreateTokenFromPasskey.Input
  ) async throws -> Operations.CreateTokenFromPasskey.Output {
    guard let ipAddressCount = RateLimitContext.ipAddressAccessCount, ipAddressCount < 30 else {
      throw HTTPError(.tooManyRequests)
    }

    // 1. Parse request payload
    guard case .json(let bodyData) = input.body else {
      return .badRequest
    }

    let credential: AuthenticationCredential
    do {
      let data = try JSONEncoder().encode(bodyData)

      credential = try JSONDecoder().decode(
        AuthenticationCredential.self,
        from: data
      )
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to parse token request payload",
        metadata: Logger.errorMetadata(error, [
          "bodyData": .string(String(describing: bodyData)),
        ])
      )
      return .badRequest
    }

    // 2. Verify and delete challenge atomically
    do {
      let challengeData = try Data(bodyData.challenge.base64decoded())
      let key = ValkeyKey("challenge:\(challengeData.base64EncodedString())")

      let data = try await cache.get(key)
      let challenge = try data.map { try JSONDecoder().decode(Challenge.self, from: Data($0)) }

      guard let challenge else {
        return .badRequest
      }

      guard challenge.userID == nil && challenge.purpose == .authentication else {
        return .badRequest
      }

      try await cache.del(keys: [key])
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify and delete authentication challenge",
        metadata: Logger.errorMetadata(error, [
          "challenge": .string(String(describing: bodyData.challenge)),
        ])
      )
      return .badRequest
    }

    // 3. Load stored credential
    let passkeyCredential: PasskeyCredential?
    do {
      passkeyCredential = try await database.read { db in
        try await PasskeyCredential
          .where { $0.id.eq(credential.id.asString()) }
          .fetchOne(db)
      }
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to load stored passkey credential",
        metadata: Logger.errorMetadata(error, [
          "credentialID": .string(credential.id.asString()),
        ])
      )
      return .badRequest
    }

    guard let passkeyCredential else {
      return .badRequest
    }

    let userID = passkeyCredential.userID
    let signCount = passkeyCredential.signCount

    // 4. Verify assertion with WebAuthn
    let verifiedAuthentication: VerifiedAuthentication
    do {
      verifiedAuthentication = try webAuthn.finishAuthentication(
        credential: credential,
        expectedChallenge: bodyData.challenge.base64decoded(),
        credentialPublicKey: Array(passkeyCredential.publicKey),
        credentialCurrentSignCount: UInt32(signCount)
      )
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify WebAuthn assertion",
        metadata: Logger.errorMetadata(error, [
          "credential": .string(String(describing: credential)),
          "challenge": .string(String(describing: bodyData.challenge)),
          "user.id": .stringConvertible(userID),
          "signCount": .stringConvertible(signCount),
        ])
      )
      return .badRequest
    }

    // 5. Update stored sign counter
    do {
      try await database.write { db in
        try await PasskeyCredential
          .update {
            $0.signCount = #sql(
              "GREATEST(\($0.signCount), \(Int64(verifiedAuthentication.newSignCount)))"
            )
          }
          .where { $0.id.eq(verifiedAuthentication.credentialID.asString()) }
          .execute(db)
      }
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to update stored sign counter",
        metadata: Logger.errorMetadata(error, [
          "credential": .string(String(describing: credential)),
          "challenge": .string(String(describing: bodyData.challenge)),
          "user.id": .stringConvertible(userID),
          "signCount": .stringConvertible(signCount),
        ])
      )
      return .badRequest
    }

    // 6. Issue application tokens
    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(
        userID: userID
      )
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to issue application tokens",
        metadata: Logger.errorMetadata(error, [
          "credential": .string(String(describing: credential)),
          "challenge": .string(String(describing: bodyData.challenge)),
          "user.id": .stringConvertible(userID),
          "signCount": .stringConvertible(signCount),
        ])
      )
      return .badRequest
    }

    return .ok(.init(body: .json(userToken)))
  }
}
