import Hummingbird
import NIOCore

struct AppRequestContext: RequestContext, RemoteAddressRequestContext {
  var coreContext: CoreRequestContextStorage
  var remoteAddress: SocketAddress?

  init(source: Source) {
    self.coreContext = .init(source: source)
    self.remoteAddress = source.channel.remoteAddress
  }
}

extension AppRequestContext {
  @TaskLocal static var current: AppRequestContext?
}
