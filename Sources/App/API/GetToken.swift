import ExtrasBase64
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey
import WebAuthn

extension API {
  func createToken(
    _ input: Operations.CreateToken.Input
  ) async throws -> Operations.CreateToken.Output {
    // 1. Parse request payload
    guard case .json(let bodyData) = input.body else {
      return .badRequest(.init())
    }

    let credential: AuthenticationCredential
    do {
      let data = try JSONEncoder().encode(bodyData)

      credential = try JSONDecoder().decode(
        AuthenticationCredential.self,
        from: data
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to parse token request payload",
        metadata: [
          "bodyData": .string(String(describing: bodyData)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }

    // 2. Verify and delete challenge atomically
    do {
      let challengeData = try Data(bodyData.challenge.base64decoded())
      let key = ValkeyKey("challenge:\(challengeData.base64EncodedString())")

      let data = try await cache.get(key)
      let challenge = try data.map { try JSONDecoder().decode(Challenge.self, from: $0) }

      guard let challenge else {
        return .badRequest(.init())
      }

      guard challenge.userID == nil && challenge.purpose == .authentication else {
        return .badRequest(.init())
      }

      try await cache.del(keys: [key])
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify and delete authentication challenge",
        metadata: [
          "challenge": .string(String(describing: bodyData.challenge)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }

    // 3. Load stored credential
    let passkeyCredential: PasskeyCredential?
    do {
      passkeyCredential = try await database.read { db in
        try await PasskeyCredential
          .select(\.self)
          .where { $0.id.eq(credential.id.asString()) }
          .limit(1)
          .fetchOne(db)
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to load stored passkey credential",
        metadata: [
          "credentialID": .string(credential.id.asString()),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }

    guard let passkeyCredential else {
      return .badRequest(.init())
    }

    // 4. Verify assertion with WebAuthn
    let verifiedAuthentication: VerifiedAuthentication
    do {
      verifiedAuthentication = try webAuthn.finishAuthentication(
        credential: credential,
        expectedChallenge: bodyData.challenge.base64decoded(),
        credentialPublicKey: Array(passkeyCredential.publicKey),
        credentialCurrentSignCount: UInt32(passkeyCredential.signCount)
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify WebAuthn assertion",
        metadata: [
          "credential": .string(String(describing: credential)),
          "challenge": .string(String(describing: bodyData.challenge)),
          "passkeyCredential": .string(String(describing: passkeyCredential)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
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
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to update stored sign counter",
        metadata: [
          "credential": .string(String(describing: credential)),
          "challenge": .string(String(describing: bodyData.challenge)),
          "passkeyCredential": .string(String(describing: passkeyCredential)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }

    // 6. Issue application tokens
    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(
        userID: passkeyCredential.userID
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to issue application tokens",
        metadata: [
          "credential": .string(String(describing: credential)),
          "challenge": .string(String(describing: bodyData.challenge)),
          "passkeyCredential": .string(String(describing: passkeyCredential)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }

    return .ok(.init(body: .json(userToken)))
  }
}
