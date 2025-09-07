import Foundation
import Hummingbird
import HummingbirdPostgres
import Logging
import Valkey
import PostgresNIO
import PostgresMigrations

func buildApplication() async throws -> some ApplicationProtocol {
  let cache = ValkeyClient(
    .hostname(ProcessInfo.processInfo.environment["VALKEY_HOSTNAME"] ?? "localhost"),
    logger: Logger(label: "Valkey")
  )
  
  let config = PostgresClient.Configuration(
    host: "localhost",
    port: 5432,
    username: "test_user",
    password: "test_password",
    database: "test_database",
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
  router.addRoutes(
    UserRouter(cache: cache, database: databaseClient).build(),
    atPath: "users"
  )

  var app = Application(
    router: router,
    services: [
      cache,
      databaseClient,
      database,
    ],
    eventLoopGroupProvider: .shared(.singletonMultiThreadedEventLoopGroup),
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
