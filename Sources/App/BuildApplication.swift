import AsyncHTTPClient
import Configuration
import Crypto
import EmailService
import Foundation
import HTTPClient
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

  let api = try API(
    cache: cache,
    database: databaseClient,
    jwtKeyCollection: jwtKeyCollection,
    webAuthn: makeWebAuth(config: config),
    appleAppSiteAssociation: makeAppleAppSiteAssociation(config: config),
    emailService: makeCloudflareEmailService(config: config),
    otpSecretKey: makeOTPSecretKey(config: config)
  )

  router.add(middleware: TracingMiddleware())
  router.add(middleware: MetricsMiddleware())
  router.add(middleware: LogRequestsMiddleware(.info))
  router.add(middleware: FileMiddleware(searchForIndexHtml: true))
  router.add(
    middleware: UserTokenMiddleware(jwtKeyCollection: jwtKeyCollection)
  )
  router.add(
    middleware: RateLimitMiddleware(
      cache: cache,
      config: try makeRateLimitConfig(arguments: arguments, config: config)
    ))
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

func makeRateLimitConfig(
  arguments: some AppArguments,
  config: ConfigReader
) throws -> RateLimitConfig {
  let config = config.scoped(to: "ratelimit")
  return try RateLimitConfig(
    durationSeconds: arguments.rateLimitDurationSeconds
      ?? config.requiredInt(forKey: "duration.seconds"),
    ipAddressMaxCount: arguments.rateLimitIPAddressMaxCount
      ?? config.requiredInt(forKey: "ip.address.max.count"),
    userTokenMaxCount: arguments.rateLimitUserTokenMaxCount
      ?? config.requiredInt(forKey: "user.token.max.count")
  )
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
    )
  )
}

func makeAppleAppSiteAssociation(config: ConfigReader) throws -> AppleAppSiteAssociation {
  try AppleAppSiteAssociation(
    webcredentials: .init(apps: [config.requiredString(forKey: "apple.app.id")]),
    appclips: .init(apps: []),
    applinks: .init(details: [])
  )
}

func makeOTPSecretKey(config: ConfigReader) throws -> SymmetricKey {
  let secretKey = try config.requiredString(forKey: "otp.secret.key")
  let secretKeyData = Data(base64Encoded: secretKey)!
  return SymmetricKey(data: secretKeyData)
}

func makeCloudflareEmailService(
  config: ConfigReader
) throws -> EmailService.Client<AsyncHTTPClient.HTTPClient> {
  let config = config.scoped(to: "cloudflare")
  return try .init(
    accountId: config.requiredString(forKey: "acocunt.id"),
    apiToken: config.requiredString(forKey: "api.token"),
    httpClient: .asyncHTTPClient(.shared)
  )
}
