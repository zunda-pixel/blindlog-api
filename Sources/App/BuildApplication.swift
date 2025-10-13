import Configuration
import Crypto
import Foundation
import Hummingbird
import HummingbirdPostgres
import JWTKit
import Logging
import OpenAPIHummingbird
import PostgresMigrations
import PostgresNIO
import SmithyIdentity
import Valkey
import WebAuthn

func buildApplication(
  _ arguments: some AppArguments
) async throws -> some ApplicationProtocol {
  let config = ConfigReader(providers: [EnvironmentVariablesProvider()])

  let logLevel =
    arguments.logLevel ?? config.string(forKey: "log.level").flatMap { Logger.Level(rawValue: $0) }
    ?? .debug

  var logger = Logger(label: "Blindlog")
  logger.logLevel = logLevel

  let cache = try makeCache(
    arguments: arguments,
    config: config,
    logger: logger
  )

  let (databaseClient, database, migrations) = try await makeDatabase(
    arguments: arguments,
    config: config,
    logger: logger
  )

  let router = Router()

  let jwtKeyCollection = JWTKeyCollection()
  let privateKey = try EdDSA.PrivateKey(
    d: config.requiredString(forKey: "eddsa.private.key"),
    curve: .ed25519
  )

  await jwtKeyCollection.add(eddsa: privateKey)
  let (awsCredential, awsRegion) = try makeAWSConfig(config: config)

  let api = try API(
    cache: cache,
    database: databaseClient,
    jwtKeyCollection: jwtKeyCollection,
    webAuthn: makeWebAuth(config: config),
    appleAppSiteAssociation: makeAppleAppSiteAssociation(config: config),
    awsCredentail: awsCredential,
    awsRegion: awsRegion
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

func makeCache(
  arguments: some AppArguments,
  config: ConfigReader,
  logger: Logger
) throws -> ValkeyClient {
  let valkeyAuthentication: ValkeyClientConfiguration.Authentication? =
    switch arguments.env {
    case .develop:
      nil
    case .production:
      try ValkeyClientConfiguration.Authentication(
        username: config.requiredString(forKey: "valkey.username"),
        password: config.requiredString(forKey: "valkey.password")
      )
    }

  let valkeyTLS: ValkeyClientConfiguration.TLS =
    switch arguments.env {
    case .develop:
      .disable
    case .production:
      try .enable(
        .clientDefault,
        tlsServerName: config.requiredString(forKey: "valkey.hostname")
      )
    }

  return try ValkeyClient(
    .hostname(config.requiredString(forKey: "valkey.hostname")),
    configuration: .init(
      authentication: valkeyAuthentication,
      tls: valkeyTLS
    ),
    logger: logger
  )
}

func makeDatabase(
  arguments: some AppArguments,
  config: ConfigReader,
  logger: Logger
) async throws -> (PostgresClient, PostgresPersistDriver, DatabaseMigrations) {
  let postgresTLS: PostgresClient.Configuration.TLS =
    switch arguments.env {
    case .develop:
      .disable
    case .production:
      .require(.clientDefault)
    }
  let databaseClient: PostgresClient

  do {
    let config = config.scoped(to: "postgres")
    let postgresConfig = try PostgresClient.Configuration(
      host: config.requiredString(forKey: "hostname"),
      username: config.requiredString(forKey: "user"),
      password: config.requiredString(forKey: "password"),
      database: config.requiredString(forKey: "db"),
      tls: postgresTLS
    )

    databaseClient = PostgresClient(
      configuration: postgresConfig,
      backgroundLogger: logger
    )
  }

  let migrations = DatabaseMigrations()

  let database = await PostgresPersistDriver(
    client: databaseClient,
    migrations: migrations,
    logger: logger
  )

  return (databaseClient, database, migrations)
}

func makeWebAuth(config: ConfigReader) throws -> WebAuthnManager {
  let config = config.scoped(to: "relying.party")

  return try WebAuthnManager(
    configuration: .init(
      relyingPartyID: config.requiredString(forKey: "id"),
      relyingPartyName: config.requiredString(forKey: "name"),
      relyingPartyOrigin: config.requiredString(forKey: "origin")
    ),
    challengeGenerator: .init {
      // https://www.w3.org/TR/webauthn-3/#sctn-appid-exclude-extension
      // challenge parameter 32 random bytes
      // 36 bytes
      Array(Data(AES.GCM.Nonce())) + Array(Data(AES.GCM.Nonce())) + Array(Data(AES.GCM.Nonce()))
    }
  )
}

func makeAppleAppSiteAssociation(config: ConfigReader) throws -> AppleAppSiteAssociation {
  try AppleAppSiteAssociation(
    webcredentials: .init(apps: [config.requiredString(forKey: "apple.app.id")]),
    appclips: .init(apps: []),
    applinks: .init(details: [])
  )
}

func makeAWSConfig(config: ConfigReader) throws -> (StaticAWSCredentialIdentityResolver, String) {
  let config = config.scoped(to: "aws")

  let credential = try StaticAWSCredentialIdentityResolver(
    AWSCredentialIdentity(
      accessKey: config.requiredString(forKey: "access.key.id"),
      secret: config.requiredString(forKey: "secret.access.key")
    ))

  let region = try config.requiredString(forKey: "region")

  return (credential, region)
}
