import Crypto
import JWTKit
import PostgresNIO
import SotoCore
import Valkey
import WebAuthn

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var jwtKeyCollection: JWTKeyCollection
  var webAuthn: WebAuthnManager
  var appleAppSiteAssociation: AppleAppSiteAssociation
  var awsClient: AWSClient
  var awsRegion: Region
  var otpSecretKey: SymmetricKey
}
