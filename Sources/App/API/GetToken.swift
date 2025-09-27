import ExtrasBase64
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import WebAuthn

extension API {
  func createToken(
    _ input: Operations.CreateToken.Input
  ) async throws -> Operations.CreateToken.Output {
    // 1. Parse request payload
    guard case .json(let bodyData) = input.body else {
      throw HTTPError(.badRequest)
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
      throw HTTPError(.badRequest)
    }

    // 2. Verify and delete challenge atomically
    do {
      let challengeData = try Data(bodyData.challenge.base64decoded())

      let row = try await database.write { db in
        try await Challenge
          .delete()
          .where {
            $0.challenge.eq(challengeData)
              .and(
                $0.userID.is(nil)
                  .and(
                    $0.purpose.eq(Challenge.Purpose.authentication)
                      .and($0.expiredDate.gt(Date.currentTimestamp))))
          }
          .returning(\.self)
          .fetchOne(db)
      }

      guard row != nil else {
        throw HTTPError(.badRequest)
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify and delete authentication challenge",
        metadata: [
          "challenge": .string(String(describing: bodyData.challenge)),
          "error": .string(String(describing: error)),
        ]
      )
      throw HTTPError(.badRequest)
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
      throw HTTPError(.badRequest)
    }

    guard let passkeyCredential else {
      throw HTTPError(.internalServerError)
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
      throw HTTPError(.badRequest)
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
      throw HTTPError(.badRequest)
    }

    // 6. Issue application tokens
    let token: String
    let refreshToken: String
    do {
      (token, refreshToken) = try await generateUserToken(
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
      throw HTTPError(.badRequest)
    }

    return .ok(
      .init(
        body: .json(
          .init(
            id: passkeyCredential.userID.uuidString,
            token: token,
            refreshToken: refreshToken
          )
        )
      )
    )
  }
}
