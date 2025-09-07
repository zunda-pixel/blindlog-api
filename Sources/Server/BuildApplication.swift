import Hummingbird
import Logging
import Valkey

func buildApplication() throws -> some ApplicationProtocol {
  let cache = ValkeyClient(
    .hostname("localhost"),
    logger: Logger(label: "Valkey")
  )

  let database = DatabaseService()

  let router = UserRouting.build(
    cache: cache,
    database: database
  )

  let logger = Logger(label: "Server")

  return Application(
    router: router,
    services: [
      cache,
      database,
    ],
    logger: logger
  )
}
