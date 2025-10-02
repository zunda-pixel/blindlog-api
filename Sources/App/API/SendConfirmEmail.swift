import AWSSDKIdentity
import AWSSESv2
import Algorithms
import Crypto
import Foundation
import Hummingbird
import HummingbirdOTP
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres

extension API {
  func sendConfirmEmail(
    _ input: Operations.SendConfirmEmail.Input
  ) async throws -> Operations.SendConfirmEmail.Output {
    guard let userID = User.currentUserID else { return .unauthorized }

    let config = try await SESv2Client.SESv2ClientConfiguration(
      awsCredentialIdentityResolver: awsCredentail,
      region: awsRegion,
    )
    let ses = SESv2Client(config: config)

    let normalizedEmail = normalizeEmail(input.query.email)

    let destination = SESv2ClientTypes.Destination(
      toAddresses: [normalizedEmail]
    )

    let subject = SESv2ClientTypes.Content(data: "Confirm your email")

    let totpPassword = HummingbirdOTP.TOTP(
      secret: String(decoding: Data(AES.GCM.Nonce()), as: UTF8.self),
      length: 6,
      timeStep: 60,
      hashFunction: .sha256
    ).compute()

    let body = SESv2ClientTypes.Body(
      html: SESv2ClientTypes.Content(data: "\(totpPassword)"),
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

    let output = try await ses.sendEmail(input: input)
    guard let messageId = output.messageId else { return .badRequest(.init()) }

    // 2. Save totp
    try await database.write { db in
      try await TOTP.insert {
        TOTP(
          password: String(totpPassword),
          messageID: messageId,
          userID: userID,
          email: normalizedEmail
        )
      }.execute(db)
    }

    return .ok
  }

  func normalizeEmail(_ email: String) -> String {
    email.trimming(while: \.isWhitespace).lowercased()
  }
}
