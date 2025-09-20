import Valkey
import PostgresNIO
import JWTKit

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var jwtKeyCollection: JWTKeyCollection
  var appleAppSiteAssociation: AppleAppSiteAssociation
}
