import Foundation
import Hummingbird
import NIOFoundationCompat
import Valkey

struct UserRouter<Context: RequestContext> {
  var cache: ValkeyClient
  var database: DatabaseService

  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .get { request, context in
        try await show(
          cache: cache,
          database: database,
          request: request
        )
      }
      .post { request, context in
        try await create(
          cache: cache,
          database: database,
          request: request,
          context: context
        )
      }
      .delete { request, context in
        try await delete(
          cache: cache,
          database: database,
          request: request
        )
      }
  }

  //MARK: Routing

  func create(
    cache: ValkeyClient,
    database: DatabaseService,
    request: Request,
    context: some RequestContext
  ) async throws -> [User] {
    do {
      let newUsers = try await request.decode(as: [NewUser].self, context: context)

      // 1. Add to Users to DB
      let addedUsers = try await addUsersToDB(
        request: request,
        newUsers: newUsers
      )

      // 2. Delete Users from Cache
      try await deleteUsersFromCache(
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

  func ids(request: Request) -> [UUID]? {
    guard let idsQuery = request.uri.queryParameters["ids"] else { return nil }

    return String(idsQuery)
      .split(separator: ",")
      .compactMap({
        UUID(uuidString: String($0))
      })
  }

  func show(
    cache: ValkeyClient,
    database: DatabaseService,
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
      let dbUsers: [User] = try await getUsersFromDB(
        request: request,
        ids: Array(leftUserIDs)
      )

      // 3. Set New Users Dat to Cache
      try await addUsersToCache(
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

  func delete(
    cache: ValkeyClient,
    database: DatabaseService,
    request: Request
  ) async throws -> HTTPResponse.Status {
    guard let ids = ids(request: request) else { throw HTTPError(.badRequest) }

    do {
      try await deleteUsersFromDB(
        request: request,
        ids: ids
      )
      try await deleteUsersFromCache(
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

  //MARK: DB

  func getUsersFromDB(
    request: Request,
    ids: [User.ID]
  ) async throws -> [User] {
    return database.users.withLock { $0.filter { ids.contains($0.id) } }
  }

  func addUsersToDB(
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

  func deleteUsersFromDB(
    request: Request,
    ids: [User.ID]
  ) async throws {
    database.users.withLock { $0.removeAll { ids.contains($0.id) } }
  }
}
