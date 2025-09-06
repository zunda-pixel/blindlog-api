import Vapor
import Valkey
import ValkeyVapor
import Foundation

// configures your application
public func configure(_ app: Application) async throws {
  // uncomment to serve files from /Public folder
  // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

  // register routes

  let valkeyClient: ValkeyClient =
    switch app.environment {
    case .production:
      ValkeyClient(.hostname(Environment.get("VALKEY_HOST")!), logger: app.logger)
    default:
      ValkeyClient(.hostname("localhost"), logger: app.logger)
    }
  app.valkey.configuration = ValkeyCache.Configuration(client: valkeyClient)
  
  app.storage[UsersStorageKey.self] = UsersStorage()
  
  try routes(app)
}


enum UsersStorageKey: StorageKey, Sendable {
  typealias Value = UsersStorage
}

import Synchronization

public final class UsersStorage: Sendable {
  let users: Mutex<[User.ID: User]> = .init([:])
}
