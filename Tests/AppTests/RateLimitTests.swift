import Foundation
import HTTPTypes
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import App

@Suite(.serialized)
struct RateLimitTests {
  @Test
  func ipAddressRateLimit() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      for _ in 0..<arguments.rateLimitIPAddressMaxCount! {
        let response = try await client.execute(
          uri: "/.well-known/apple-app-site-association",
          method: .get,
          headers: [
            .xForwardedFor: ipAddress
          ]
        )
        #expect(response.status == .ok)
      }

      let response = try await client.execute(
        uri: "/.well-known/apple-app-site-association",
        method: .get,
        headers: [
          .xForwardedFor: ipAddress
        ]
      )
      #expect(response.status == .tooManyRequests)
    }
  }

  @Test
  func userTokenRateLimit() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString

    try await app.test(.router) { client in
      // 1. Add User to DB
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .xForwardedFor: ipAddress
        ]
      )
      #expect(newUserResponse.status == .ok)
      let newUser = try JSONDecoder().decode(
        Components.Schemas.UserToken.self,
        from: newUserResponse.body
      )
      for _ in 0..<arguments.rateLimitUserTokenMaxCount! {
        // 2. Get User to DB
        let getResponse = try await client.execute(
          uri: "/me",
          method: .get,
          headers: [
            .authorization: "Bearer \(newUser.token)",
            .xForwardedFor: ipAddress,
          ]
        )

        #expect(getResponse.status == .ok)
        let getUser = try JSONDecoder().decode(User.self, from: getResponse.body)
        #expect(newUser.userID == getUser.id.uuidString)
      }

      let getResponse = try await client.execute(
        uri: "/me",
        method: .get,
        headers: [
          .authorization: "Bearer \(newUser.token)",
          .xForwardedFor: ipAddress,
        ]
      )

      #expect(getResponse.status == .tooManyRequests)
    }
  }

  @Test
  func userTokenRateLimitPerEndpoint() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString
    
    try await app.test(.router) { client in
      // 1. Add User to DB
      for _ in 0..<30 {
        let newUserResponse = try await client.execute(
          uri: "/user",
          method: .post,
          headers: [
            .xForwardedFor: ipAddress
          ]
        )
        #expect(newUserResponse.status == .ok)
      }
      
      let newUserResponse = try await client.execute(
        uri: "/user",
        method: .post,
        headers: [
          .xForwardedFor: ipAddress
        ]
      )
      #expect(newUserResponse.status == .internalServerError)
    }
  }
}
