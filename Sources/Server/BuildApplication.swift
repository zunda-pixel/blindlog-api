import Foundation
import Hummingbird
import HummingbirdPostgres
import Logging
import PostgresMigrations
import PostgresNIO
import Valkey

func buildApplication() async throws -> some ApplicationProtocol {
  let environment = Environment()

  let cache = ValkeyClient(
    .hostname(environment.get("VALKEY_HOSTNAME")!),
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
