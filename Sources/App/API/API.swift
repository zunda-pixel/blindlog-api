import JWTKit
import PostgresNIO
import Valkey
import WebAuthn

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var jwtKeyCollection: JWTKeyCollection
  var webAuthn: WebAuthnManager
  var appleAppSiteAssociation: AppleAppSiteAssociation
}
