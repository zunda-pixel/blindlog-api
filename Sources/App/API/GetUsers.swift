import Foundation
import Hummingbird
import PostgresNIO
import SQLKit
import Valkey

extension API {
  func getUsers(
    _ input: Operations.getUsers.Input
  ) async throws -> Operations.getUsers.Output {
    let ids: [UUID] = input.query.ids.compactMap { UUID(uuidString: $0) }

    do {
      // 1. Get Users from Cache and Update Expiration if exits
      let cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        ids: ids
      )

      // 2. Get Users from DB that is not in Cache
      let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
      let dbUsers: [User] = try await getUsersFromDatabase(
        ids: Array(leftUserIDs)
      )

      // 3. Set New Users Dat to Cache
      try await addUsersToCache(
        users: dbUsers
      )

      let users = cacheUsers + dbUsers

      return .ok(
        .init(
          body: .json(
            users.map {
              .init(id: $0.id.uuidString)
            })))
    } catch {
      //      logger.error(
      //        """
      //        Failed to fetch users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
      //        Error: \(String(reflecting: error))
      //        """
      //      )
      throw HTTPError(.internalServerError)
    }
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
    let query: PostgresQuery = """
        SELECT id
        FROM users
        WHERE users.id = ANY(\(ids))
      """
    let rows = try await database.query(query).collect()

    let decoder = SQLRowDecoder()
    let users: [User] = try rows.map { row in
      return try row.sql().decode(model: User.self, with: decoder)
    }
    return users
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
