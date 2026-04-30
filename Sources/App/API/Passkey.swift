import Foundation
import Hummingbird
import OpenAPIRuntime
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey
import WebAuthn

extension API {
  func addPasskey(
    _ input: Operations.AddPasskey.Input
  ) async throws -> Operations.AddPasskey.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
      userTokenAccessCount < 30
    else {
      throw HTTPError(.tooManyRequests)
    }
    // 1. Parse request payload
    guard case .json(let body) = input.body else { return .badRequest }
    let registrationCredential: RegistrationCredential
    do {
      let bodyData = try JSONEncoder().encode(body)
      registrationCredential = try JSONDecoder().decode(
        RegistrationCredential.self,
        from: bodyData
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.registration_decode_failed",
        "Failed to decode WebAuthn registration",
        metadata: AppLogMetadata.userID(userID),
        error: error
      )
      return .badRequest
    }
    // 2. Verify and delete challenge atomically
    let challengeData = Data(input.query.challenge.data)
    do {
      let key = ValkeyKey("challenge:\(challengeData.base64EncodedString())")

      let data = try await cache.get(key)
      let challenge = try data.map { try JSONDecoder().decode(Challenge.self, from: Data($0)) }

      guard let challenge else {
        return .badRequest
      }

      guard challenge.userID == userID && challenge.purpose == .registration else {
        return .badRequest
      }

      try await cache.del(keys: [key])
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.registration_challenge_verify_failed",
        "Failed to verify and delete registration challenge",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("get_delete")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    // 3. Validate WebAuthn registration data
    let credential: Credential
    do {
      credential = try await webAuthn.finishRegistration(
        challenge: Array(input.query.challenge.data),
        credentialCreationData: registrationCredential,
        confirmCredentialIDNotRegisteredYet: { credentialID in
          let credential = try await database.read { db in
            try await PasskeyCredential
              .where { $0.id.eq(credentialID) }
              .select { _ in 1 }
              .fetchOne(db)
          }

          return credential == nil
        }
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.registration_validate_failed",
        "Failed to validate WebAuthn registration",
        metadata: AppLogMetadata.userID(userID),
        error: error
      )
      return .badRequest
    }
    // 4. Persist credential metadata
    do {
      try await database.write { db in
        try await PasskeyCredential.insert {
          PasskeyCredential(
            id: registrationCredential.id.asString(),
            userID: userID,
            publicKey: Data(credential.publicKey),
            signCount: Int64(credential.signCount)
          )
        } onConflict: {
          $0.id
        }
        .execute(db)
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.credential_persist_failed",
        "Failed to persist passkey credential",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("insert")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok
  }
}
