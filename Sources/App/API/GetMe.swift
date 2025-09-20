import Foundation
import PostgresNIO
import Hummingbird
import SQLKit
import Valkey

extension API {
  func getMe(_ input: Operations.getMe.Input) async throws -> Operations.getMe.Output {
    guard let userID = BearerAuthenticateUser.current?.userID else {
      throw HTTPError(.unauthorized)
    }
    
    let user = try await getUser(id: userID)
    
    return .ok(.init(body: .json(.init(
      id: user.id.uuidString
    ))))
  }
  
  fileprivate func getUser(id: UUID) async throws -> User {
    // 1. Get User from Cache and Update Expiration if exits
    let cacheUser = try await getUserFromCacheAndUpdateExpiration(
      id: id
    )

    if let cacheUser {
      return cacheUser
    }

    // 2. Get User from DB that is not in Cache
    let dbUser: User? = try await getUserFromDatabase(
      id: id
    )

    guard let dbUser else { throw HTTPError(.notFound) }

    // 3. Set New User to Cache
    try await addUserToCache(
      user: dbUser
    )
    return dbUser
  }
  
  fileprivate func addUserToCache(
    user: User
  ) async throws {
    try await cache.set(
      ValkeyKey("user:\(user.id.uuidString)"),
      value: try JSONEncoder().encode(user),
      expiration: .seconds(60 * 10)  // 10 minutes
    )
  }
  
  fileprivate func getUserFromDatabase(
    id: User.ID
  ) async throws -> User? {
    let query: PostgresQuery = """
        SELECT id
        FROM users
        WHERE users.id = \(id)
        LIMIT 1
      """
    let rows = try await database.query(query).collect()

    if let row = rows.first {
      return try row.sql().decode(model: User.self, with: SQLRowDecoder())
    } else {
      return nil
    }
  }
  
  fileprivate func getUserFromCacheAndUpdateExpiration(
    id: User.ID
  ) async throws -> User? {
    let userData = try await cache.getex(
      ValkeyKey("user:\(id.uuidString)"),
      expiration: .seconds(60 * 10)  // 10 minutes
    )

    if let userData {
      return try JSONDecoder().decode(User.self, from: userData)
    } else {
      return nil
    }
  }
}
