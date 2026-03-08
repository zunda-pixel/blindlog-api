import Algorithms
import Crypto
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import SotoSESv2
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
    let ses = SESv2(client: awsClient, region: awsRegion)

    let normalizedEmail = normalizeEmail(input.query.email)

    let destination = SESv2.Destination(
      toAddresses: [normalizedEmail]
    )

    let subject = SESv2.Content(data: "Confirm your email")

    let otpPassword = OTPGenerator().generate(length: 6)

    let body = SESv2.Body(
      html: SESv2.Content(data: otpPassword),
    )

    let simple = SESv2.Message(body: body, subject: subject)

    let content = SESv2.EmailContent(
      simple: simple
    )

    let request = SESv2.SendEmailRequest(
      content: content,
      destination: destination,
      fromEmailAddress: "support@blindlog.me"
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
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to save OTP to db",
        metadata: [
          "userID": .string(userID.uuidString),
          "email": .string(normalizedEmail),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    // 2. Send email
    do {
      _ = try await ses.sendEmail(request)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to send email",
        metadata: [
          "userID": .string(userID.uuidString),
          "email": .string(normalizedEmail),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    return .ok
  }

  func normalizeEmail(_ email: String) -> String {
    email.trimming(while: \.isWhitespace).lowercased()
  }
}
