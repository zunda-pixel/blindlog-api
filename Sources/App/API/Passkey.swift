import Foundation
import Hummingbird
import Logging
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
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to decode WebAuthn registration",
        metadata: Logger.errorMetadata(error, [
          "body": .string(String(describing: body)),
        ])
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
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify and delete registration challenge",
        metadata: Logger.errorMetadata(error, [
          "challenge": .string(challengeData.base64EncodedString()),
          "user.id": .stringConvertible(userID),
        ])
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
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to validate WebAuthn registration",
        metadata: Logger.errorMetadata(error, [
          "registrationCredential": .string(String(describing: registrationCredential)),
          "user.id": .stringConvertible(userID),
        ])
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
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to persist passkey credential",
        metadata: Logger.errorMetadata(error, [
          "credentialID": .string(registrationCredential.id.asString()),
          "user.id": .stringConvertible(userID),
        ])
      )
      return .badRequest
    }

    return .ok
  }
}
