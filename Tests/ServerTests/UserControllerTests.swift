import Testing
import VaporTesting
@testable import Server
import Foundation
import NIOCore

@Suite
struct UserControllerTests {
  @Test
  func createAndGetUsers() async throws {
    try await withApp(configure: { app in
      try await configure(app)
    }){ app in
      let users: [NewUser] = [
        .init(name: "John Doe"),
        .init(name: "Mary Jane")
      ]
      
      let body = try JSONEncoder().encode(users)
      
      try await withThrowingTaskGroup { group in
        group.addTask {
          try await app.valkey.client.run()
        }
        group.addTask {
          var newUsers: [User] = []
          // 1. Add Users to DB
          try await app.testing().test(
            .post,
            "/users",
            body: ByteBuffer(data: body)
          ) { response in
            #expect(response.status == .ok)
            newUsers = try await response.content.decode([User].self)
          }
          // 2. Get Users from DB and add to Cache
          try await app.testing().test(
            .get,
            "/users/:ids"
          ) { request in
            try request.query.encode(
              ["ids": newUsers.map(\.id.uuidString).joined(separator: ",")]
            )
          } afterResponse: { response in
            #expect(response.status == .ok)
            let dbUsers = try await response.content.decode([User].self)
            #expect(Set(newUsers) == Set(dbUsers))
          }
          // 3. Get Users from Cache
          try await app.testing().test(
            .get,
            "/users/:ids"
          ) { request in
            try request.query.encode(
              ["ids": newUsers.map(\.id.uuidString).joined(separator: ",")]
            )
          } afterResponse: { response in
            #expect(response.status == .ok)
            let cachedUsers = try await response.content.decode([User].self)
            #expect(Set(newUsers) == Set(cachedUsers))
          }
        }
        
        let _ = try await group.next()
        group.cancelAll()
      }
    }
  }
}

import Vapor

struct _URLQueryContainer: URLQueryContainer {
  var url: URI
  let contentConfiguration: ContentConfiguration
  
  func decode<D>(
    _ decodable: D.Type,
    using decoder: any URLQueryDecoder) throws -> D where D: Decodable {
    return try decoder.decode(D.self, from: self.url)
  }
  
  mutating func encode(
    _ encodable: some Encodable,
    using encoder: any URLQueryEncoder
  ) throws {
    try encoder.encode(encodable, to: &self.url)
  }
}
