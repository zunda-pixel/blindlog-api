import Foundation
import Hummingbird
import Logging
import Valkey

func buildApplication() throws -> some ApplicationProtocol {
  let cache = ValkeyClient(
    .hostname(ProcessInfo.processInfo.environment["VALKEY_HOSTNAME"] ?? "localhost"),
    logger: Logger(label: "Valkey")
  )

  let database = DatabaseService()

  let router = Router()
  router.addRoutes(
    UserRouter(cache: cache, database: database).build(),
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
