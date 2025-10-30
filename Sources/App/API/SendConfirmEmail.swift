import AWSSDKIdentity
import AWSSESv2
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
  func sendConfirmEmail(
    _ input: Operations.SendConfirmEmail.Input
  ) async throws -> Operations.SendConfirmEmail.Output {
    guard let userID = User.currentUserID else { return .unauthorized }
    let ses: SESv2Client

    do {
      let config = try await SESv2Client.SESv2ClientConfiguration(
        awsCredentialIdentityResolver: awsCredentail,
        region: awsRegion,
      )
      ses = SESv2Client(config: config)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to initialize SESv2Client",
        metadata: [
          "userID": .string(userID.uuidString),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    let normalizedEmail = normalizeEmail(input.query.email)

    let destination = SESv2ClientTypes.Destination(
      toAddresses: [normalizedEmail]
    )

    let subject = SESv2ClientTypes.Content(data: "Confirm your email")

    let otpPassword = OTPGenerator().generate(length: 6)

    let body = SESv2ClientTypes.Body(
      html: SESv2ClientTypes.Content(data: otpPassword),
    )

    let simple = SESv2ClientTypes.Message(body: body, subject: subject)

    let content = SESv2ClientTypes.EmailContent(
      simple: simple
    )

    let input = SendEmailInput(
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
      _ = try await ses.sendEmail(input: input)
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
