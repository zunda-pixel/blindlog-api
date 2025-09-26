public import ArgumentParser
import Hummingbird
import Logging

@main
struct AppCommand: AsyncParsableCommand, AppArguments {
  @Option(name: .shortAndLong)
  var hostname: String = "127.0.0.1"

  @Option(name: .shortAndLong)
  var port: Int = 8080

  @Option(name: .shortAndLong)
  var logLevel: Logger.Level?

  @Option(name: .shortAndLong)
  var env: EnvironmentLevel = .develop

  func run() async throws {
    let app = try await buildApplication(self)
    try await app.runService()
  }
}

protocol AppArguments {
  var hostname: String { get }
  var port: Int { get }
  var logLevel: Logger.Level? { get }
  var env: EnvironmentLevel { get }
}

/// Extend `Logger.Level` so it can be used as an argument
#if hasFeature(RetroactiveAttribute)
  extension Logger.Level: @retroactive ExpressibleByArgument {}
#else
  extension Logger.Level: ExpressibleByArgument {}
#endif

enum EnvironmentLevel: String, ExpressibleByArgument {
  case develop
  case production
}
