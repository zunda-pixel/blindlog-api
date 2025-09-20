import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import App

struct TestArguments: AppArguments {
  var hostname: String = "127.0.0.1"
  var port: Int = 8080
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

  @Test(arguments: [["john-doe@example.com", "mary-ane@example.com"]])
  func createAndGetUsers(emails: [String]) async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)

    try await app.test(.router) { client in
      // 1. Add Users to Database
      let newUsers = try await withThrowingTaskGroup { group in
        for email in emails {
          group.addTask {
            let newUser: User = try await client.execute(
              uri: "/signup?email=\(email)",
              method: .post
            ) { response in
              #expect(response.status == .ok)
              return try JSONDecoder().decode(User.self, from: response.body)
            }
            return newUser
          }
        }

        var users: [User] = []

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
        #expect(Set(newUsers) == Set(dbUsers))
      }

      // 3. Get Users from Cache
      try await client.execute(
        uri: "/users?ids=\(idsQuery)",
        method: .get,
      ) { response in
        #expect(response.status == .ok)
        let cachedUsers = try JSONDecoder().decode([User].self, from: response.body)
        #expect(Set(newUsers) == Set(cachedUsers))
      }
    }
  }
}
