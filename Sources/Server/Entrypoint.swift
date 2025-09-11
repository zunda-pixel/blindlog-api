import ArgumentParser
import Hummingbird
import Logging
import NIOCore
import NIOPosix
import Valkey

@main
struct Entrypoint: AsyncParsableCommand, AppArguments {
  @Option(name: .shortAndLong)
  var hostname: String = "127.0.0.1"

  @Option(name: .shortAndLong)
  var port: Int = 8080

  func run() async throws {
    let app = try await buildApplication(self)
    do {
      try await app.runService()
    } catch {
      app.logger.error("\(error.localizedDescription)")
      throw error
    }
  }
}

protocol AppArguments {
  var hostname: String { get }
  var port: Int { get }
}
