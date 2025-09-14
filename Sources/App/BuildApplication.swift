import Foundation
import Hummingbird
import HummingbirdPostgres
import Logging
import PostgresMigrations
import PostgresNIO
import Valkey

func buildApplication(
  _ arguments: some AppArguments
) async throws -> some ApplicationProtocol {
  let environment = Environment()
  var logger = Logger(label: "App")
  logger.logLevel = .debug

  let valkeyAuthentication: ValkeyClientConfiguration.Authentication?
  if let username = environment.get("VALKEY_USERNAME"),
    let password = environment.get("VALKEY_PASSWORD")
  {
    valkeyAuthentication = ValkeyClientConfiguration.Authentication(
      username: username, password: password)
  } else {
    valkeyAuthentication = nil
  }

  #if DEBUG
  let valkeyTLS: ValkeyClientConfiguration.TLS = .disable
  #else
  let valkeyTLS: ValkeyClientConfiguration.TLS = try .enable(.clientDefault, tlsServerName: environment.get("VALKEY_HOSTNAME")!)
  #endif
  
  let cache = ValkeyClient(
    .hostname(environment.get("VALKEY_HOSTNAME")!),
    configuration: .init(
      authentication: valkeyAuthentication,
      tls: valkeyTLS
    ),
    logger: logger
  )
  
  #if DEBUG
  let postgresTLS: PostgresClient.Configuration.TLS = .disable
  #else
  let postgresTLS: PostgresClient.Configuration.TLS = .require(.clientDefault)
  #endif

  let config = PostgresClient.Configuration(
    host: environment.get("POSTGRES_HOSTNAME")!,
    username: environment.get("POSTGRES_USER")!,
    password: environment.get("POSTGRES_PASSWORD")!,
    database: environment.get("POSTGRES_DB")!,
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
  router.addRoutes(
    UsersRouter(cache: cache, database: databaseClient).build(),
    atPath: "users"
  )
  router.addRoutes(
    MeRouter(cache: cache, database: databaseClient).build(),
    atPath: "me"
  )
  router.addRoutes(
    SignupRouter(cache: cache, database: databaseClient).build(),
  )

  router.addRoutes(
    AppleAppSiteAssosiationRouter(
      appIds: [environment.get("APPLE_APP_ID")!]
    ).build()
  )

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
    logger: Logger(label: "Server")
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
