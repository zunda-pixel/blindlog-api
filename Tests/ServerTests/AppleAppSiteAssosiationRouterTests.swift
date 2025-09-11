import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import Server

@Suite
struct AppleAppSiteAssosiationRouterTests {
  @Test
  func wellKnownAppleAppSiteAssociation() async throws {
    do {
      let arguments = TestArguments()
      let app = try await buildApplication(arguments)
      
      try await app.test(.router) { client in
        let response = try await client.execute(
          uri: "/.well-known/apple-app-site-association",
          method: .get
        )
        
        #expect(response.headers[.contentType] == "application/json; charset=utf-8")
      }
    } catch {
      print(error)
    }
  }
}
