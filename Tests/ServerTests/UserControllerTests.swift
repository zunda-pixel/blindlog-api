import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import Server

@Suite
struct UserControllerTests {
  @Test
  func createUsers() async throws {
    let app = try await buildApplication()

    try await app.test(.router) { client in
      let users: [NewUser] = [
        .init(name: "John Doe"),
        .init(name: "Mary Jane"),
      ]

      let body = try JSONEncoder().encode(users)

      // 1. Add Users to DB
      let response = try await client.execute(
        uri: "/users",
        method: .post,
        headers: [:],
        body: ByteBuffer(data: body)
      )

      #expect(response.status == .ok)
      let addedUsers = try JSONDecoder().decode([User].self, from: response.body)
      print(addedUsers)
    }
  }

  @Test
  func createAndGetUsers() async throws {
    let app = try await buildApplication()

    try await app.test(.router) { client in
      let users: [NewUser] = [
        .init(name: "John Doe"),
        .init(name: "Mary Jane"),
      ]

      let body = try JSONEncoder().encode(users)

      // 1. Add Users to Database
      let newUsers: [User] = try await client.execute(
        uri: "/users",
        method: .post,
        body: ByteBuffer(data: body)
      ) { response in
        #expect(response.status == .ok)
        return try JSONDecoder().decode([User].self, from: response.body)
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
      
      // 4. Delete Users from Database
      try await client.execute(
        uri: "/users?ids=\(idsQuery)",
        method: .delete,
      ) { response in
        #expect(response.status == .ok)
      }
    }
  }
}
