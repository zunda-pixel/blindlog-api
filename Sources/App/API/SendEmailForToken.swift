import Crypto
import EmailService
import ExtrasBase64
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
  func sendEmailForToken(
    _ input: Operations.SendEmailForToken.Input
  ) async throws -> Operations.SendEmailForToken.Output {
    guard let ipAddressAccessCount = RateLimitContext.ipAddressAccessCount,
      ipAddressAccessCount < 30
    else {
      throw HTTPError(.tooManyRequests)
    }
    let email: String = normalizeEmail(input.query.email)
    let challenge = [UInt8].random(count: 32)

    // 2. Generate OTP
    let otpPassword = OTPGenerator().generate(length: 6)
    let message = Data(otpPassword.utf8)
    let hashedOTP = HMAC<SHA256>.authenticationCode(for: message, using: otpSecretKey)

    let otp = OTPEmailAuthentication(
      challenge: Data(challenge),
      email: email,
      hashedPassword: Data(hashedOTP)
    )

    // 3. Save OTP to cache
    do {
      let key = ValkeyKey("OTPEmailAuthentication:\(otp.challenge.base64EncodedString())")
      let otpData = try JSONEncoder().encode(otp)

      try await cache.set(
        key,
        value: otpData,
        expiration: .seconds(60 * 1)  // 1 minutes
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.email.otp_cache_write_failed",
        "Failed to store authentication OTP",
        metadata: AppLogMetadata.emailSHA256(email).merging([
          "cache.operation": .string("set")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    // 4. Send Email

    let emailMessage = EmailMessage(
      to: email,
      from: "support@blindlog.me",
      subject: "Confirm your email",
      text: otpPassword
    )

    do {
      _ = try await emailService.send(emailMessage)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.email.send_failed",
        "Failed to send email",
        metadata: AppLogMetadata.emailSHA256(email),
        error: error
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(challenge))))
  }
}
