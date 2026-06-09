import Crypto
import Foundation
import JWTKit
import PostgresNIO
import Valkey

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var cloudflareImagesClient: any CloudflareImagesClientProtocol
  var jwtKeyCollection: JWTKeyCollection
  var jwtConfiguration: JWTConfiguration
  var webAuthn: any WebAuthnProtocol
  var appleAppSiteAssociation: AppleAppSiteAssociation
  var emailService: any EmailServiceProtocol
  var otpSecretKey: SymmetricKey
  var passConfiguration: PassConfiguration?
}
