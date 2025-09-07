import Hummingbird
import Logging
import Valkey

func buildApplication() throws -> some ApplicationProtocol {
  let cache = ValkeyClient(
    .hostname("localhost"),
    logger: Logger(label: "Valkey")
  )

  let database = DatabaseService()

  let router = Router()
  router.addRoutes(
    UserRouting(cache: cache, database: database).build(),
    atPath: "users"
  )

  let logger = Logger(label: "Server")

  return Application(
    router: router,
    services: [
      cache
    ],
    eventLoopGroupProvider: .shared(.singletonMultiThreadedEventLoopGroup),
    logger: logger
  )
}
