import Algorithms
import Crypto
import EmailService
import Foundation
import Hummingbird
import Logging
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey

extension API {
  func sendConfirmEmail(
    _ input: Operations.SendConfirmEmail.Input
  ) async throws -> Operations.SendConfirmEmail.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard let userTokenAccessCount = RateLimitContext.userTokenAccessCount,
      userTokenAccessCount < 30
    else {
      throw HTTPError(.tooManyRequests)
    }

    let normalizedEmail = normalizeEmail(input.query.email)
    let otpPassword = OTPGenerator().generate(length: 6)

    let message = EmailMessage(
      to: normalizedEmail,
      from: "support@blindlog.me",
      subject: "Confirm your email",
      text: otpPassword
    )

    // 1. Save OTP to db
    do {
      let message = Data(otpPassword.utf8)
      let hashedOTP = HMAC<SHA256>.authenticationCode(for: message, using: otpSecretKey)

      let otp = OTPEmailRegistration(
        hashedPassword: Data(hashedOTP),
        userID: userID,
        email: normalizedEmail
      )

      let otpData = try JSONEncoder().encode(otp)

      try await cache.set(
        ValkeyKey("OTPEmailRegistration:\(userID)"),
        value: otpData,
        expiration: .seconds(60 * 1)
      )
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to save OTP to db",
        metadata: Logger.errorMetadata(
          error,
          [
            "user.id": .stringConvertible(userID),
            "email": .string(normalizedEmail),
          ]
        )
      )
      return .badRequest
    }

    // 2. Send email
    do {
      _ = try await self.emailService.send(message)
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to send email",
        metadata: Logger.errorMetadata(
          error,
          [
            "user.id": .stringConvertible(userID),
            "email": .string(normalizedEmail),
          ]
        )
      )
      return .badRequest
    }

    return .ok
  }

  func normalizeEmail(_ email: String) -> String {
    email.trimming(while: \.isWhitespace).lowercased()
  }
}
