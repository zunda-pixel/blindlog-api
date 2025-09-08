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
      .post { request, context in
        try await create(
          request: request,
          context: context
        )
      }
      .delete { request, context in
        try await delete(
          request: request
        )
      }
  }

  //MARK: Routing

  func create(
    request: Request,
    context: some RequestContext
  ) async throws -> [User] {
    do {
      let newUsers = try await request.decode(as: [NewUser].self, context: context)

      // 1. Add to Users to DB
      let addedUsers = try await addUsersToDatabase(
        request: request,
        newUsers: newUsers
      )

      // 2. Delete Users from Cache
      try await deleteUsersFromCache(
        ids: addedUsers.map(\.id)
      )
      return addedUsers
    } catch {
      logger.error(
        """
        Failed to save users
        Error: \(error)
        """
      )
      throw HTTPError(.internalServerError)
    }
  }

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

  func delete(
    request: Request
  ) async throws -> HTTPResponse.Status {
    guard let ids = ids(request: request) else { throw HTTPError(.badRequest) }

    do {
      try await deleteUsersFromDatabase(
        request: request,
        ids: ids
      )
      try await deleteUsersFromCache(
        ids: ids
      )
      return .ok
    } catch {
      logger.error(
        """
        Failed to delete users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
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

  func deleteUsersFromCache(
    ids: [User.ID]
  ) async throws {
    try await cache.del(keys: ids.map { ValkeyKey("user:\($0.uuidString)") })
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

  func addUsersToDatabase(
    request: Request,
    newUsers: [NewUser]
  ) async throws -> [User] {
    let users: [User] = newUsers.map { user in
      let user = User(id: UUID(), name: user.name)
      return user
    }

    try await database.withTransaction(logger: Logger(label: "Database INSERT")) { connection in
      for user in users {
        let query: PostgresQuery = "INSERT INTO users (id, name) VALUES (\(user.id), \(user.name))"

        try await connection.query(query, logger: Logger(label: "Nested Database INSERT"))
      }
    }

    return users
  }

  func deleteUsersFromDatabase(
    request: Request,
    ids: [User.ID]
  ) async throws {
    let query: PostgresQuery = "DELETE FROM users WHERE id = ANY(\(ids))"

    try await database.query(query)
  }
}
