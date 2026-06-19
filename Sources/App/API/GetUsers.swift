import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey

extension API {
  func getUsers(
    _ input: Operations.GetUsers.Input
  ) async throws -> Operations.GetUsers.Output {
    let ids = input.query.ids.compactMap { UUID(uuidString: $0) }
    guard ids.count == input.query.ids.count else {
      return .badRequest
    }

    // 1. Get Users from Cache and Update Expiration if exits
    let cacheUsers: [User]
    do {
      cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        ids: ids
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.cache_read_failed",
        "Failed to fetch users from cache and update expiration",
        metadata: [
          "cache.operation": .string("getex"),
          "user.ids": .array(ids.map { .string($0.uuidString) }),
        ],
        error: error
      )
      cacheUsers = []
    }

    // 2. Get Users from DB that is not in Cache
    let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
    let dbUsers: [User]
    do {
      dbUsers = try await getUsersFromDatabase(
        ids: Array(leftUserIDs)
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.db_read_failed",
        "Failed to fetch users from database",
        metadata: [
          "db.operation": .string("select"),
          "user.ids": .array(ids.map { .string($0.uuidString) }),
        ],
        error: error
      )
      return .badRequest
    }
    // 3. Set new users data to cache
    do {
      try await addUsersToCache(
        users: dbUsers
      )
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "user.cache_write_failed",
        "Failed to write users to cache",
        metadata: [
          "cache.operation": .string("set"),
          "user.count": .stringConvertible(dbUsers.count),
          "user.ids": .array(dbUsers.map { .string($0.id.uuidString) }),
        ],
        error: error
      )
    }

    let users: [Components.Schemas.User] = (cacheUsers + dbUsers).map {
      .init(id: $0.id.uuidString)
    }

    return .ok(.init(body: .json(users)))
  }

  fileprivate func addUsersToCache(
    users: [User]
  ) async throws {
    let encoder = JSONEncoder()

    try await cache.withConnection { connection in
      try await connection.multi()
      for user in users {
        try await connection.set(
          ValkeyKey("user:\(user.id.uuidString)"),
          value: try encoder.encode(user),
          expiration: .seconds(60 * 10)  // 10 minutes
        )
      }
      try await connection.exec()
    }
  }

  fileprivate func getUsersFromDatabase(
    ids: [User.ID]
  ) async throws -> [User] {
    return try await database.read { db in
      try await User
        .select(\.self)
        .where { user in
          user.id.in(ids)
        }
        .fetchAll(db)
    }
  }

  fileprivate func getUsersFromCacheAndUpdateExpiration(
    ids: [User.ID]
  ) async throws -> [User] {
    guard !ids.isEmpty else { return [] }

    let decoder = JSONDecoder()

    let commands: [any ValkeyCommand] = ids.map { id in
      GETEX(
        ValkeyKey("user:\(id.uuidString)"),
        expiration: .seconds(60 * 10)  // 10 minutes
      )
    }

    let results = try await cache.withConnection { connection in
      await connection.execute(commands)
    }

    var users: [User] = []
    for result in results {
      let token = try result.get()
      guard let userData = try token.decode(as: RESPBulkString?.self) else {
        continue
      }
      users.append(try decoder.decode(User.self, from: Data(userData)))
    }

    return users
  }
}
