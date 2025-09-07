import Foundation
import Hummingbird
import Valkey

enum UserRouting {
  static func build(
    cache: ValkeyClient,
    database: DatabaseService
  ) -> Router<BasicRequestContext> {
    let router = Router()

    router.get("users") { request, context in
      try await show(
        cache: cache,
        database: database,
        request: request
      )
    }

    router.post("users") { request, context in
      try await create(
        cache: cache,
        database: database,
        request: request,
        context: context
      )
    }

    router.delete("users") { request, context in
      try await delete(
        cache: cache,
        database: database,
        request: request
      )
    }

    return router
  }

  //MARK: Routing

  static func create(
    cache: ValkeyClient,
    database: DatabaseService,
    request: Request,
    context: some RequestContext
  ) async throws -> [User] {
    do {
      let newUsers = try await request.decode(as: [NewUser].self, context: context)

      // 1. Add to Users to DB
      let addedUsers = try await addUsersToDB(
        database: database,
        request: request,
        newUsers: newUsers
      )

      // 2. Delete Users from Cache
      try await deleteUsersFromCache(
        cache: cache,
        ids: addedUsers.map(\.id)
      )
      return addedUsers
    } catch {
      //      req.application.logger.error(
      //        """
      //        Failed to save users
      //        Error: \(error)
      //        """)
      print(error)
      throw HTTPError(.internalServerError)
    }
  }

  static func ids(request: Request) -> [UUID]? {
    guard let idsQuery = request.uri.queryParameters["ids"] else { return nil }

    return String(idsQuery)
      .split(separator: ",")
      .compactMap({
        UUID(uuidString: String($0))
      })
  }

  static func show(
    cache: ValkeyClient,
    database: DatabaseService,
    request: Request
  ) async throws -> [User] {
    guard let ids = ids(request: request) else { throw HTTPError(.badRequest) }

    guard !ids.isEmpty else { throw HTTPError(.noContent) }

    do {
      // 1. Get Users from Cache and Update Expiration if exits
      let cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        cache: cache,
        ids: ids
      )

      // 2. Get Users from DB that is not in Cache
      let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
      let dbUsers: [User] = try await getUsersFromDB(
        database: database,
        request: request,
        ids: Array(leftUserIDs)
      )

      // 3. Set New Users Dat to Cache
      try await addUsersToCache(
        cache: cache,
        users: dbUsers
      )
      return cacheUsers + dbUsers
    } catch {
      //      req.application.logger.error(
      //        """
      //        Failed to fetch users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
      //        Error: \(error)
      //        """)
      throw HTTPError(.internalServerError)
    }
  }

  static func delete(
    cache: ValkeyClient,
    database: DatabaseService,
    request: Request
  ) async throws -> HTTPResponse.Status {
    guard let ids = ids(request: request) else { throw HTTPError(.badRequest) }

    do {
      try await deleteUsersFromDB(
        database: database,
        request: request,
        ids: ids
      )
      try await deleteUsersFromCache(
        cache: cache,
        ids: ids
      )
      return .ok
    } catch {
      //      req.application.logger.error(
      //        """
      //        Failed to delete users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
      //        Error: \(error)
      //        """)
      throw HTTPError(.internalServerError)
    }
  }

  //MARK: Cache

  static func getUsersFromCacheAndUpdateExpiration(
    cache: ValkeyClient,
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

  static func addUsersToCache(
    cache: ValkeyClient,
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

  static func deleteUsersFromCache(
    cache: ValkeyClient,
    ids: [User.ID]
  ) async throws {
    try await cache.del(keys: ids.map { ValkeyKey("user:\($0.uuidString)") })
  }

  //MARK: DB

  static func getUsersFromDB(
    database: DatabaseService,
    request: Request,
    ids: [User.ID]
  ) async throws -> [User] {
    return database.users.withLock { $0.filter { ids.contains($0.id) } }
  }

  static func addUsersToDB(
    database: DatabaseService,
    request: Request,
    newUsers: [NewUser]
  ) async throws -> [User] {
    let users: [User] = newUsers.map { user in
      let user = User(id: UUID(), name: user.name, birthDay: user.birthDay)
      return user
    }

    database.users.withLock { $0.append(contentsOf: users) }

    return users
  }

  static func deleteUsersFromDB(
    database: DatabaseService,
    request: Request,
    ids: [User.ID]
  ) async throws {
    database.users.withLock { $0.removeAll { ids.contains($0.id) } }
  }
}
