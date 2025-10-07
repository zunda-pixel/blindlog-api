import Crypto
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
  func createTokenFromEmail(
    _ input: Operations.CreateTokenFromEmail.Input
  ) async throws -> Operations.CreateTokenFromEmail.Output {
    // 1. Parse request payload
    guard case .json(let bodyData) = input.body else {
      return .badRequest
    }

    // 2. Verify and delete challenge atomically
    let email: String = normalizeEmail(bodyData.email)
    do {
      let challengeData = try Data(bodyData.challenge.base64decoded())
      let key = ValkeyKey("TOTPEmailAuthentication:\(challengeData.base64EncodedString())")

      let data = try await cache.get(key)
      let challenge = try data.map {
        try JSONDecoder().decode(TOTPEmailAuthentication.self, from: $0)
      }

      guard let challenge else {
        return .badRequest
      }

      guard challenge.email == email else {
        return .badRequest
      }

      guard challenge.challenge == Data(base64Encoded: bodyData.challenge) else {
        return .unauthorized
      }

      guard Data(SHA256.hash(data: Data(bodyData.otp.utf8))) == challenge.hashedPassword else {
        return .unauthorized
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
      return .badRequest
    }

    // 3. fetch user with email
    let userID: UUID?
    
    do {
      userID = try await database.read { db in
        try await UserEmail
          .where { $0.email.eq(email) }
          .select { ($0.userID) }
          .fetchOne(db)
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to fetch user",
        metadata: [
          "challenge": .string(String(describing: bodyData.challenge)),
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }
    
    guard let userID else {
      return .notFound
    }

    // 4. Issue application tokens
    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(
        userID: userID
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to issue application tokens",
        metadata: [
          "email": .string(bodyData.email),
          "userID": .string(userID.uuidString),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    return .ok(.init(body: .json(userToken)))
  }
}
