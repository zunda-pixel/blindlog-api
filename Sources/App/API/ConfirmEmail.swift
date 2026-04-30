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

    guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
      userTokenAccessCount < 30
    else {
      throw HTTPError(.tooManyRequests)
    }

    let email = normalizeEmail(input.query.email)
    // 1. Verify otp
    do {
      let otpData = try await cache.get(ValkeyKey("OTPEmailRegistration:\(userID.uuidString)"))
      guard let otpData else {
        return .badRequest
      }

      let otp = try JSONDecoder().decode(OTPEmailRegistration.self, from: Data(otpData))

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
      AppRequestContext.current?.logger.appError(
        eventName: "user.email.otp_verify_failed",
        "Failed to verify otp",
        metadata: AppLogMetadata.userID(userID)
          .merging(AppLogMetadata.emailSHA256(email)) { _, new in new }
          .merging(["cache.operation": .string("get")]) { _, new in new },
        error: error
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
        } onConflict: { columns in
          (columns.userID, columns.email)
        }.execute(db)
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.email.persist_failed",
        "Failed to save user email to db",
        metadata: AppLogMetadata.userID(userID)
          .merging(AppLogMetadata.emailSHA256(email)) { _, new in new }
          .merging(["db.operation": .string("insert")]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    do {
      try await cache.del(keys: [ValkeyKey("user:\(userID.uuidString)")])
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.cache_delete_failed",
        "Failed to delete old user from cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("delete")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok
  }
}
