import Logging
import NIOCore
import NIOPosix
import ValkeyVapor
import Vapor
import Valkey

@main
enum Entrypoint {
  static func main() async throws {
    var env = try Environment.detect()
    try LoggingSystem.bootstrap(from: &env)

    let app = try await Application(env)
    
    let valkeyClient: ValkeyClient = switch app.environment {
    case .production:
      ValkeyClient(.hostname(Environment.get("VALKEY_HOST")!), logger: app.logger)
    default:
      ValkeyClient(.hostname("localhost"), logger: app.logger)
    }
    app.valkey.configuration = ValkeyCache.Configuration(client: valkeyClient)

    do {
      try await configure(app)
      await withTaskGroup(of: Void.self) { group in
        group.addTask { try? await app.run() }
        group.addTask { try? await app.valkey.client.run() }
        await group.waitForAll()
      }

    } catch {
      app.logger.report(error: error)
      try? await app.shutdown()
      throw error
    }
    try await app.shutdown()
  }
}
