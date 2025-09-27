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
    let ids: [UUID] = input.query.ids.compactMap { UUID(uuidString: $0) }

    // 1. Get Users from Cache and Update Expiration if exits
    let cacheUsers: [User]
    do {
      cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        ids: ids
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to fetch users from cache and update expiration",
        metadata: [
          "userIDs": .array(ids.map { .string($0.uuidString) }),
          "error": .string(String(describing: error))
        ]
      )
      throw HTTPError(.badRequest)
    }

    // 2. Get Users from DB that is not in Cache
    let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
    let dbUsers: [User]
    do {
      dbUsers = try await getUsersFromDatabase(
        ids: Array(leftUserIDs)
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to fetch users from database",
        metadata: [
          "userIDs": .array(ids.map { .string($0.uuidString) }),
          "error": .string(String(describing: error))
        ]
      )
      throw HTTPError(.badRequest)
    }
    // 3. Set new users data to cache
    do {
      try await addUsersToCache(
        users: dbUsers
      )
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .warning,
        "Failed to write users to cache",
        metadata: [
          "users": .array(dbUsers.map { .string(String(describing: $0)) }),
          "error": .string(String(describing: error))
        ]
      )
      throw HTTPError(.internalServerError)
    }

    let users = cacheUsers + dbUsers

    return .ok(
      .init(
        body: .json(
          users.map {
            .init(id: $0.id.uuidString)
          })))
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
    return try await cache.withConnection { connection in
      return try await withThrowingTaskGroup(of: Optional<User>.self) { group in
        let decoder = JSONDecoder()

        for id in ids {
          group.addTask {
            let userData = try await connection.getex(
              ValkeyKey("user:\(id.uuidString)"),
              expiration: .seconds(60 * 10)  // 10 minutes
            )

            if let userData {
              return try decoder.decode(User.self, from: userData)
            } else {
              return nil
            }
          }
        }

        var users: [User] = []

        for try await user in group {
          guard let user else { continue }
          users.append(user)
        }

        return users
      }
    }
  }
}
