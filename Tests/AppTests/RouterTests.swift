import Foundation
import HummingbirdTesting
import Logging
import NIOCore
import Testing

@testable import App

struct TestArguments: AppArguments {
  var hostname: String = "127.0.0.1"
  var port: Int = 8080
  var logLevel: Logger.Level? = .debug
}

@Suite(.serialized)
struct RouterTests {
  @Test
  func wellKnownAppleAppSiteAssociation() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      let response = try await client.execute(
        uri: "/.well-known/apple-app-site-association",
        method: .get
      )

      #expect(response.headers[.contentType] == "application/json; charset=utf-8")
    }
  }

  @Test
  func createUser() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      // 1. Add User to DB
      let signupResponse = try await client.execute(
        uri: "/user",
        method: .post
      )
      #expect(signupResponse.status == .ok)
      let addedUser = try JSONDecoder().decode(UserToken.self, from: signupResponse.body)
      // 2. Get User to DB
      let getResponse = try await client.execute(
        uri: "/me",
        method: .get,
        headers: [
          .authorization: "Bearer \(addedUser.token)"
        ]
      )

      #expect(getResponse.status == .ok)
      let getUser = try JSONDecoder().decode(User.self, from: getResponse.body)
      #expect(addedUser.id == getUser.id)
    }
  }

  @Test
  func createAndGetUsers() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      // 1. Add Users to Database
      let newUsers = try await withThrowingTaskGroup { group in
        for _ in 0..<10 {
          group.addTask {
            let newUser: UserToken = try await client.execute(
              uri: "/user",
              method: .post
            ) { response in
              #expect(response.status == .ok)
              return try JSONDecoder().decode(UserToken.self, from: response.body)
            }
            return newUser
          }
        }

        var users: [UserToken] = []

        for try await user in group {
          users.append(user)
        }

        return users
      }

      let idsQuery = newUsers.map(\.id.uuidString).joined(separator: ",")

      // 2. Get Users from Database and add to Cache
      try await client.execute(
        uri: "/users?ids=\(idsQuery)",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let dbUsers = try JSONDecoder().decode([User].self, from: response.body)
        #expect(Set(newUsers.map(\.id)) == Set(dbUsers.map(\.id)))
      }

      // 3. Get Users from Cache
      try await client.execute(
        uri: "/users?ids=\(idsQuery)",
        method: .get,
      ) { response in
        #expect(response.status == .ok)
        let cachedUsers = try JSONDecoder().decode([User].self, from: response.body)
        #expect(Set(newUsers.map(\.id)) == Set(cachedUsers.map(\.id)))
      }
    }
  }

  @Test
  func refreshToken() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      // 1. Add User to DB
      let signupResponse = try await client.execute(
        uri: "/user",
        method: .post
      )
      #expect(signupResponse.status == .ok)
      let addedUser = try JSONDecoder().decode(UserToken.self, from: signupResponse.body)
      // 2. Get User to DB
      let refreshResponse = try await client.execute(
        uri: "/refreshToken",
        method: .post,
        body: ByteBuffer(data: JSONEncoder().encode(["refreshToken": addedUser.refreshToken]))
      )

      #expect(refreshResponse.status == .ok)
      let getUser = try JSONDecoder().decode(UserToken.self, from: refreshResponse.body)
      #expect(addedUser.id == getUser.id)
    }
  }

  @Test
  func challengeForRegistration() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      // 1. Add User to DB
      let signupResponse = try await client.execute(
        uri: "/user",
        method: .post
      )
      #expect(signupResponse.status == .ok)
      let addedUser = try JSONDecoder().decode(UserToken.self, from: signupResponse.body)
      // 2. Get User to DB
      let challengeResponse = try await client.execute(
        uri: "/challenge",
        method: .post,
        headers: [
          .authorization: "Bearer \(addedUser.token)"
        ]
      )

      #expect(challengeResponse.status == .ok)
      let challenge = Data(buffer: challengeResponse.body)
      print(challenge)
    }
  }

  @Test
  func challengeForAuthorization() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      let response = try await client.execute(
        uri: "/challenge",
        method: .post
      )

      #expect(response.status == .ok)
      let challenge = Data(buffer: response.body)
      print(challenge)
    }
  }

  @Test(.disabled("This test can only be run manually by providing the correct passkey"))
  func addPasskey() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      // 1. Add User to DB
      let signupResponse = try await client.execute(
        uri: "/user",
        method: .post
      )
      #expect(signupResponse.status == .ok)
      let addedUser = try JSONDecoder().decode(UserToken.self, from: signupResponse.body)
      // 2. Get User to DB
      let challengeResponse = try await client.execute(
        uri: "/challenge",
        method: .post,
        headers: [
          .authorization: "Bearer \(addedUser.token)"
        ]
      )

      #expect(challengeResponse.status == .ok)
      let challenge = try #require(Data(base64Encoded: String(buffer: challengeResponse.body)))

      let body = Components.Schemas.AddPasskey(
        id: .init(),
        rawId: .init(),
        _type: .init(),
        response: .init(
          clientDataJSON: "",
          attestationObject: "",
        )
      )

      let bodyData = try JSONEncoder().encode(body)

      let addPasskeyResponse = try await client.execute(
        uri: "/passkey?challenge=\(challenge.base64EncodedString())",
        method: .post,
        headers: [
          .authorization: "Bearer \(addedUser.token)"
        ],
        body: ByteBuffer(data: bodyData)
      )

      #expect(addPasskeyResponse.status == .ok)
    }
  }
}
