import Hummingbird
import ServiceLifecycle
import Synchronization

final class DatabaseService: Service {
  func run() async throws {}

  let users: Mutex<[User]> = .init([])
}
