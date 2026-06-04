import AsyncHTTPClient
import Crypto
import EmailService
import Foundation
import JWTKit
import PostgresNIO
import Valkey
import WebAuthn

protocol EmailServiceProtocol: Sendable {
  func send(_ email: EmailMessage) async throws -> EmailResponse.Result
}

extension EmailService.Client: EmailServiceProtocol {}

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var cloudflareImagesClient: any CloudflareImagesClientProtocol
  var jwtKeyCollection: JWTKeyCollection
  var webAuthn: WebAuthnManager
  var appleAppSiteAssociation: AppleAppSiteAssociation
  var emailService: any EmailServiceProtocol
  var otpSecretKey: SymmetricKey
}
