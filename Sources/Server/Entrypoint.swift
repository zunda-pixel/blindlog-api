import ArgumentParser
import Hummingbird
import Logging
import NIOCore
import NIOPosix
import Valkey

@main
struct Entrypoint: AsyncParsableCommand {
  func run() async throws {
    let app = try await buildApplication()
    do {
      try await app.runService()
    } catch {
      app.logger.error("\(error.localizedDescription)")
      throw error
    }
  }
}
