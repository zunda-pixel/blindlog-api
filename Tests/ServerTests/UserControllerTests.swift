import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import Server

@Suite(.serialized)
struct UserControllerTests {
  @Test
  func createUser() async throws {
    let app = try await buildApplication()

    try await app.test(.router) { client in
      let user = NewUser(name: "John Doe")

      let body = try JSONEncoder().encode(user)

      // 1. Add Users to DB
      let response = try await client.execute(
        uri: "/me",
        method: .post,
        headers: [:],
        body: ByteBuffer(data: body)
      )

      #expect(response.status == .ok)
      let addedUser = try JSONDecoder().decode(User.self, from: response.body)
      print(addedUser)
    }
  }

  @Test
  func createAndGetUsers() async throws {
    let app = try await buildApplication()

    try await app.test(.router) { client in
      let users: [NewUser] = [
        NewUser(name: "John Doe"),
        NewUser(name: "Mary Jane"),
      ]

      // 1. Add Users to Database
      let newUsers = try await withThrowingTaskGroup { group in
        for user in users {
          group.addTask {
            let body = try JSONEncoder().encode(user)
            let newUser: User = try await client.execute(
              uri: "/me",
              method: .post,
              body: ByteBuffer(data: body)
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
