import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import Server

@Suite
struct UserControllerTests {
  @Test(arguments: ["test@example.com"])
  func createUser(email: String) async throws {
    let app = try await buildApplication()

    try await app.test(.router) { client in
      // 1. Add User to DB
      let signupResponse = try await client.execute(
        uri: "/signup?email=\(email)",
        method: .post
      )
      #expect(signupResponse.status == .ok)
      let addedUser = try JSONDecoder().decode(User.self, from: signupResponse.body)
      #expect(addedUser.email == email)
      
      // 2. Get User to DB
      let getResponse = try await client.execute(
        uri: "/me?id=\(addedUser.id)",
        method: .get
      )

      #expect(getResponse.status == .ok)
      let getUser = try JSONDecoder().decode(User.self, from: getResponse.body)
      #expect(addedUser == getUser)
    }
  }

  @Test(arguments: [["john-doe@example.com", "mary-ane@example.com",]])
  func createAndGetUsers(emails: [String]) async throws {
    let app = try await buildApplication()

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
