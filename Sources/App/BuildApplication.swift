import Crypto
import Foundation
import Hummingbird
import HummingbirdPostgres
import JWTKit
import Logging
import OpenAPIHummingbird
import PostgresMigrations
import PostgresNIO
import Valkey
import WebAuthn

func buildApplication(
  _ arguments: some AppArguments
) async throws -> some ApplicationProtocol {
  let environment = Environment()
  let logLevel =
    arguments.logLevel ?? environment.get("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) }
    ?? .debug

  var logger = Logger(label: "Blindlog")
  logger.logLevel = logLevel

  let valkeyAuthentication: ValkeyClientConfiguration.Authentication? =
    switch arguments.env {
    case .develop:
      nil
    case .production:
      try ValkeyClientConfiguration.Authentication(
        username: environment.require("VALKEY_USERNAME"),
        password: environment.require("VALKEY_PASSWORD")
      )
    }

  let valkeyTLS: ValkeyClientConfiguration.TLS =
    switch arguments.env {
    case .develop:
      .disable
    case .production:
      try .enable(
        .clientDefault,
        tlsServerName: environment.require("VALKEY_HOSTNAME")
      )
    }

  let cache = try ValkeyClient(
    .hostname(environment.require("VALKEY_HOSTNAME")),
    configuration: .init(
      authentication: valkeyAuthentication,
      tls: valkeyTLS
    ),
    logger: logger
  )

  let postgresTLS: PostgresClient.Configuration.TLS =
    switch arguments.env {
    case .develop:
      .disable
    case .production:
      .require(.clientDefault)
    }

  let config = try PostgresClient.Configuration(
    host: environment.get("POSTGRES_HOSTNAME")!,
    username: environment.require("POSTGRES_USER"),
    password: environment.require("POSTGRES_PASSWORD"),
    database: environment.require("POSTGRES_DB"),
    tls: postgresTLS
  )

  let databaseClient = PostgresClient(
    configuration: config,
    backgroundLogger: logger
  )

  let migrations = DatabaseMigrations()

  let database = await PostgresPersistDriver(
    client: databaseClient,
    migrations: migrations,
    logger: logger
  )

  let router = Router()

  let jwtKeyCollection = JWTKeyCollection()

  let privateKey = try EdDSA.PrivateKey(
    d: environment.require("EdDSA_PRIVATE_KEY"),
    curve: .ed25519
  )

  await jwtKeyCollection.add(eddsa: privateKey)
  let api = API(
    cache: cache,
    database: databaseClient,
    jwtKeyCollection: jwtKeyCollection,
    webAuthn: WebAuthnManager(
      configuration: .init(
        relyingPartyID: try environment.require("RELYING_PARTY_ID"),
        relyingPartyName: try environment.require("RELYING_PARTY_NAME"),
        relyingPartyOrigin: try environment.require("RELYING_PARTY_ORIGIN")
      ),
      challengeGenerator: .init {
        Array(Data(AES.GCM.Nonce()))
      }
    ),
    appleAppSiteAssociation: .init(
      webcredentials: .init(apps: [try environment.require("APPLE_APP_ID")]),
      appclips: .init(apps: []),
      applinks: .init(details: [])
    )
  )

  router.add(middleware: TracingMiddleware())
  router.add(middleware: MetricsMiddleware())
  router.add(middleware: LogRequestsMiddleware(.info))
  router.add(middleware: FileMiddleware(searchForIndexHtml: true))
  router.add(
    middleware: BearerTokenMiddleware(jwtKeyCollection: jwtKeyCollection)
  )
  router.add(middleware: OpenAPIRequestContextMiddleware())

  try api.registerHandlers(on: router)

  var app = Application(
    router: router,
    configuration: .init(
      address: .hostname(arguments.hostname, port: arguments.port)
    ),
    services: [
      databaseClient,
      database,
      cache,
    ],
    logger: logger
  )

  app.beforeServerStarts {
    try await migrations.apply(
      client: databaseClient,
      groups: [.persist],
      logger: Logger(label: "Postgres Migrations"),
      dryRun: false
    )
  }

  return app
}
