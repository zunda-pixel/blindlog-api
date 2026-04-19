import Crypto
import JWTKit
import PostgresNIO
import EmailService
import AsyncHTTPClient
import Valkey
import WebAuthn
import Foundation

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var jwtKeyCollection: JWTKeyCollection
  var webAuthn: WebAuthnManager
  var appleAppSiteAssociation: AppleAppSiteAssociation
  var emailService: EmailService.Client<AsyncHTTPClient.HTTPClient>
  var otpSecretKey: SymmetricKey
}
