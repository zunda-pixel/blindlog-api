import AWSSDKIdentity
import AWSSESv2
import Crypto
import ExtrasBase64
import Foundation
import Hummingbird
import HummingbirdOTP
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
    let email: String = normalizeEmail(input.query.email)
    let challenge: [UInt8] =
      Array(Data(AES.GCM.Nonce()))
      + Array(Data(AES.GCM.Nonce()))
      + Array(Data(AES.GCM.Nonce()))

    // 1. initialize SES Client
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
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    // 2. Generate OTP
    let otpPassword = generateOTP()
    let message = Data(otpPassword.utf8)
    let hashedOTP = HMAC<SHA256>.authenticationCode(for: message, using: otpSecretKey)

    let otp = OTPEmailAuthentication(
      challenge: Data(challenge),
      email: email,
      hashedPassword: Data(hashedOTP)
    )

    // 3. Save TOTP to cache
    do {
      let key = ValkeyKey("OTPEmailAuthentication:\(otp.challenge.base64EncodedString())")
      let otpData = try JSONEncoder().encode(otp)

      try await cache.set(
        key,
        value: otpData,
        expiration: .seconds(60 * 1)  // 1 minutes
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to update stored sign counter",
        metadata: [
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    // 4. Send Email

    let destination = SESv2ClientTypes.Destination(
      toAddresses: [email]
    )

    let subject = SESv2ClientTypes.Content(data: "Confirm your email")

    let body = SESv2ClientTypes.Body(
      html: SESv2ClientTypes.Content(data: "\(otpPassword)"),
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

    do {
      _ = try await ses.sendEmail(input: input)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to send email",
        metadata: [
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(challenge))))
  }
}
