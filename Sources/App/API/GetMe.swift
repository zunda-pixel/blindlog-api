import Foundation
import Hummingbird
import PostgresKit
import Records
import SQLKit
import Valkey

extension API {
  func getMe(_ input: Operations.GetMe.Input) async throws -> Operations.GetMe.Output {
    guard let userID = User.currentUserID else {
      return .unauthorized
    }
    let user: User?
    do {
      user = try await getUser(id: userID)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to fetch user profile",
        metadata: [
          "userID": .string(userID.uuidString),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    guard let user else {
      return .notFound
    }

    let responseUser = Components.Schemas.User(id: user.id.uuidString)
    
    return .ok(.init(body: .json(responseUser)))
  }

  fileprivate func getUser(id: UUID) async throws -> User? {
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

    guard let dbUser else { return nil }

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
    return try await database.read { db in
      try await User
        .select(\.self)
        .where { $0.id.eq(id) }
        .limit(1)
        .fetchOne(db)
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
