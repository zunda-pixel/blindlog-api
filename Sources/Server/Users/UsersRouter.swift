import Foundation
import Hummingbird
import NIOFoundationCompat
import PostgresKit
import PostgresNIO
import Valkey

struct UsersRouter<Context: RequestContext> {
  var cache: ValkeyClient
  var logger: Logger = Logger(label: "UsersRouter")
  var database: PostgresClient

  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .get { request, context in
        try await show(
          request: request
        )
      }
  }

  //MARK: Routing

  func ids(request: Request) -> [UUID]? {
    guard let idsQuery = request.uri.queryParameters["ids"] else { return nil }

    return String(idsQuery)
      .split(separator: ",")
      .compactMap({
        UUID(uuidString: String($0))
      })
  }

  func show(
    request: Request
  ) async throws -> [User] {
    guard let ids = ids(request: request) else { throw HTTPError(.badRequest) }

    guard !ids.isEmpty else { throw HTTPError(.noContent) }

    do {
      // 1. Get Users from Cache and Update Expiration if exits
      let cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        ids: ids
      )

      // 2. Get Users from DB that is not in Cache
      let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
      let dbUsers: [User] = try await getUsersFromDatabase(
        request: request,
        ids: Array(leftUserIDs)
      )

      // 3. Set New Users Dat to Cache
      try await addUsersToCache(
        users: dbUsers
      )
      return cacheUsers + dbUsers
    } catch {
      logger.error(
        """
        Failed to fetch users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
        Error: \(error)
        """
      )
      throw HTTPError(.internalServerError)
    }
  }

  //MARK: Cache

  func getUsersFromCacheAndUpdateExpiration(
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

  func addUsersToCache(
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

  //MARK: Database

  func getUsersFromDatabase(
    request: Request,
    ids: [User.ID]
  ) async throws -> [User] {
    let query: PostgresQuery = "SELECT id, name FROM users where id = ANY(\(ids))"

    let rows = try await database.query(query).collect()

    let decoder = SQLRowDecoder()
    let users: [User] = try rows.map { row in
      return try row.sql().decode(model: User.self, with: decoder)
    }
    return users
  }
}
