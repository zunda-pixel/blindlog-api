import Foundation
import Hummingbird
import OpenAPIRuntime
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import UUIDV7
import Valkey
import WebAuthn

extension API {
  func addPasskey(
    _ input: Operations.AddPasskey.Input
  ) async throws -> Operations.AddPasskey.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
      userTokenAccessCount < RateLimitContext.authenticationEndpointMaxCount
    else {
      throw HTTPError(.tooManyRequests)
    }
    // 1. Parse request payload
    guard case .json(let body) = input.body else { return .badRequest(.invalidRequest) }
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
      return .badRequest(.registrationDecodeFailed)
    }
    // 2. Verify and delete challenge atomically
    let challengeData = Data(input.query.challenge.data)
    do {
      let key = ValkeyKey("challenge:\(challengeData.base64EncodedString())")

      let data = try await cache.getdel(key)
      let challenge = try data.map { try JSONDecoder().decode(Challenge.self, from: Data($0)) }

      guard let challenge else {
        AppRequestContext.current?.logger.appLog(
          level: .warning,
          eventName: "auth.passkey.registration_challenge_missing",
          "Registration challenge was not found",
          metadata: AppLogMetadata.userID(userID)
        )
        return .badRequest(.challengeVerifyFailed)
      }

      guard challenge.userID == userID && challenge.purpose == .registration else {
        AppRequestContext.current?.logger.appLog(
          level: .warning,
          eventName: "auth.passkey.registration_challenge_mismatch",
          "Registration challenge did not match the current user or purpose",
          metadata: AppLogMetadata.userID(userID)
        )
        return .badRequest(.challengeVerifyFailed)
      }

    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.registration_challenge_verify_failed",
        "Failed to verify and delete registration challenge",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("getdel")
        ]) { _, new in new },
        error: error
      )
      return .badRequest(.challengeVerifyFailed)
    }

    // 3. Validate WebAuthn registration data
    let credential: Credential
    do {
      credential = try await webAuthn.finishRegistration(
        challenge: Array(input.query.challenge.data),
        credentialCreationData: registrationCredential,
        requireUserVerification: false,
        supportedPublicKeyAlgorithms: .supported,
        pemRootCertificatesByFormat: [:],
        confirmCredentialIDNotRegisteredYet: { credentialID in
          let credential = try await database.read { db in
            try await PasskeyCredential
              .where { $0.id.eq(credentialID) }
              .select { _ in 1 }
              .fetchOne(db)
          }

          guard credential == nil else {
            throw PasskeyRegistrationError.credentialIDAlreadyExists
          }
          return true
        }
      )
    } catch PasskeyRegistrationError.credentialIDAlreadyExists {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "auth.passkey.credential_already_exists",
        "Passkey credential is already registered",
        metadata: AppLogMetadata.userID(userID)
      )
      return .badRequest(.credentialAlreadyExists)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.passkey.registration_validate_failed",
        "Failed to validate WebAuthn registration",
        metadata: AppLogMetadata.userID(userID),
        error: error
      )
      return .badRequest(.registrationValidateFailed)
    }
    // 4. Persist credential metadata
    do {
      try await database.write { db in
        let passkeyCredential = PasskeyCredential(
          id: registrationCredential.id.asString(),
          userID: userID,
          publicKey: Data(credential.publicKey)
        )

        try await PasskeyCredential.insert {
          passkeyCredential
        }
        .execute(db)

        try await PasskeyCredentialSignCount.insert {
          PasskeyCredentialSignCount(
            id: UUID(uuidString: UUID.uuidV7String())!,
            passkeyCredentialID: passkeyCredential.id,
            signCount: Int64(credential.signCount)
          )
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
      return .badRequest(.persistFailed)
    }

    return .ok
  }
}

private enum PasskeyRegistrationError: Error {
  case credentialIDAlreadyExists
}
