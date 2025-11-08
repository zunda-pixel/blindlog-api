import Algorithms
import Crypto
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey

extension API {
  func confirmEmail(
    _ input: Operations.ConfirmEmail.Input
  ) async throws -> Operations.ConfirmEmail.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    let email = normalizeEmail(input.query.email)
    // 1. Verify otp
    do {
      let otpData = try await cache.get(ValkeyKey("OTPEmailRegistration:\(userID.uuidString)"))
      guard let otpData else {
        return .badRequest
      }

      let otp = try JSONDecoder().decode(OTPEmailRegistration.self, from: otpData)

      guard otp.userID == userID && otp.email == email else {
        return .badRequest
      }
      let message = Data(input.query.password.utf8)
      guard
        HMAC<SHA256>.isValidAuthenticationCode(
          otp.hashedPassword,
          authenticating: message,
          using: otpSecretKey
        )
      else {
        return .unauthorized
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify otp",
        metadata: [
          "userID": .string(userID.uuidString),
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    // 2. Save email to db
    do {
      try await database.write { db in
        try await UserEmail.insert {
          UserEmail(
            userID: userID,
            email: email
          )
        }.execute(db)
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to save user email to db",
        metadata: [
          "userID": .string(userID.uuidString),
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    do {
      try await cache.del(keys: [ValkeyKey("user:\(userID.uuidString)")])
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to delete old user from cache",
        metadata: [
          "userID": .string(userID.uuidString),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    return .ok
  }
}
