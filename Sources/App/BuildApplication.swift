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

  let valkeyAuthentication: ValkeyClientConfiguration.Authentication?
  if let username = environment.get("VALKEY_USERNAME"),
    let password = environment.get("VALKEY_PASSWORD")
  {
    valkeyAuthentication = ValkeyClientConfiguration.Authentication(
      username: username, password: password)
  } else {
    valkeyAuthentication = nil
  }

  let cache = ValkeyClient(
    .hostname(environment.get("VALKEY_HOSTNAME")!),
    configuration: .init(authentication: valkeyAuthentication),
    logger: Logger(label: "Valkey")
  )

  let config = PostgresClient.Configuration(
    host: environment.get("POSTGRES_HOSTNAME")!,
    username: environment.get("POSTGRES_USER")!,
    password: environment.get("POSTGRES_PASSWORD")!,
    database: environment.get("POSTGRES_DB")!,
    tls: .disable
  )

  let databaseClient = PostgresClient(
    configuration: config,
    backgroundLogger: Logger(label: "PosgresClient")
  )

  let migrations = DatabaseMigrations()

  let database = await PostgresPersistDriver(
    client: databaseClient,
    migrations: migrations,
    logger: Logger(label: "Postgres")
  )

  let router = Router()
//  router.addRoutes(
//    UsersRouter(cache: cache, database: databaseClient).build(),
//    atPath: "users"
//  )
//  router.addRoutes(
//    MeRouter(cache: cache, database: databaseClient).build(),
//    atPath: "me"
//  )
//  router.addRoutes(
//    SignupRouter(cache: cache, database: databaseClient).build(),
//  )
//
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
      cache,
      databaseClient,
      database,
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
