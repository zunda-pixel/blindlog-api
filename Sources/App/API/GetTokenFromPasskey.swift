import ExtrasBase64
import Foundation
import Hummingbird
import Records
import SQLKit
import StructuredQueriesPostgres
import UUIDV7
import Valkey
import WebAuthn

extension API {
  func createTokenFromPasskey(
    _ input: Operations.CreateTokenFromPasskey.Input
  ) async throws -> Operations.CreateTokenFromPasskey.Output {
    guard let ipAddressCount = RateLimitContext.ipAddressAccessCount,
      ipAddressCount < RateLimitContext.authenticationEndpointMaxCount
    else {
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
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.payload_decode_failed",
        "Failed to parse token request payload",
        error: error
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
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.challenge.verify_failed",
        "Failed to verify and delete authentication challenge",
        metadata: [
          "auth.flow": .string("passkey"),
          "cache.operation": .string("get_delete"),
        ],
        error: error
      )
      return .badRequest
    }

    // 3. Load stored credential and the highest observed sign counter
    let passkeyCredential: PasskeyCredential?
    let signCount: Int64?
    do {
      (passkeyCredential, signCount) = try await database.read { db in
        let passkeyCredential =
          try await PasskeyCredential
          .where { $0.id.eq(credential.id.asString()) }
          .fetchOne(db)

        let signCount =
          try await PasskeyCredentialSignCount
          .where { $0.passkeyCredentialID.eq(credential.id.asString()) }
          .order { ($0.signCount.desc(), $0.id.desc()) }
          .select { $0.signCount }
          .limit(1)
          .fetchOne(db)

        return (passkeyCredential, signCount)
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.credential_load_failed",
        "Failed to load stored passkey credential",
        metadata: [
          "db.operation": .string("select")
        ],
        error: error
      )
      return .badRequest
    }

    guard let passkeyCredential, let signCount else {
      return .badRequest
    }

    let userID = passkeyCredential.userID

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
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.assertion_verify_failed",
        "Failed to verify WebAuthn assertion",
        metadata: AppLogMetadata.userID(userID).merging([
          "webauthn.sign_count": .stringConvertible(signCount)
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    // 5. Append observed sign counter
    do {
      try await database.write { db in
        try await PasskeyCredentialSignCount.insert {
          PasskeyCredentialSignCount(
            id: UUID(uuidString: UUID.uuidV7String())!,
            passkeyCredentialID: verifiedAuthentication.credentialID.asString(),
            signCount: Int64(verifiedAuthentication.newSignCount)
          )
        }
        .execute(db)
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.sign_count_append_failed",
        "Failed to append observed sign counter",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("insert"),
          "webauthn.sign_count": .stringConvertible(signCount),
          "webauthn.new_sign_count": .stringConvertible(verifiedAuthentication.newSignCount),
        ]) { _, new in new },
        error: error
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
      AppRequestContext.current?.logger.appError(
        eventName: "auth.token.issue_failed",
        "Failed to issue application tokens",
        metadata: AppLogMetadata.userID(userID).merging([
          "auth.flow": .string("passkey")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok(.init(body: .json(userToken)))
  }
}
