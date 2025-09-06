import Foundation
import NIOCore
import Valkey
import ValkeyVapor
import Vapor

struct UserController: RouteCollection {
  func boot(routes: any Vapor.RoutesBuilder) throws {
    let users = routes.grouped("users")

    users.post(use: create)

    users.group(":ids") { users in
      users.get(use: show)
      users.delete(use: delete)
    }
  }

  func create(req: Request) async throws -> [User] {
    do {
      let newUsers: [NewUser] = try await req.content.decode([NewUser].self, using: JSONDecoder())

      // 1. Add to Users to DB
      let addedUsers = try await addUsersToDB(
        request: req,
        newUsers: newUsers
      )

      // 2. Delete Users from Cache
      try await deleteUsersFromCache(
        client: req.application.valkey.client,
        ids: addedUsers.map(\.id)
      )
      return addedUsers
    } catch {
      req.application.logger.error(
        """
        Failed to save users
        Error: \(error)
        """)
      throw Abort(.internalServerError)
    }
  }

  func ids(req: Request) throws -> [UUID] {
    return try req.query.get(String.self, at: "ids")
      .split(separator: ",")
      .compactMap({
        UUID(uuidString: String($0))
      })
  }

  func show(req: Request) async throws -> [User] {
    let ids = try ids(req: req)

    guard !ids.isEmpty else { throw Abort(.noContent) }
    
    do {
      // 1. Get Users from Cache and Update Expiration if exits
      let cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        client: req.application.valkey.client,
        ids: ids
      )

      // 2. Get Users from DB that is not in Cache
      let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
      let dbUsers: [User] = try await getUsersFromDB(
        request: req,
        ids: Array(leftUserIDs)
      )

      // 3. Set New Users Dat to Cache
      try await addUsersToCache(
        client: req.application.valkey.client,
        users: dbUsers
      )
      return cacheUsers + dbUsers
    } catch {
      req.application.logger.error(
        """
        Failed to fetch users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
        Error: \(error)
        """)
      throw Abort(.internalServerError)
    }
  }

  func delete(req: Request) async throws -> HTTPStatus {
    let ids = try ids(req: req)

    do {
      try await deleteUsersFromDB(
        request: req,
        ids: ids
      )
      try await deleteUsersFromCache(
        client: req.application.valkey.client,
        ids: ids
      )
      return HTTPStatus.noContent
    } catch {
      req.application.logger.error(
        """
        Failed to delete users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
        Error: \(error)
        """)
      throw Abort(.internalServerError)
    }
  }

  //MARK: Cache

  func getUsersFromCacheAndUpdateExpiration(
    client: ValkeyClient,
    ids: [User.ID]
  ) async throws -> [User] {
    return try await client.withConnection { connection in
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
    client: ValkeyClient,
    users: [User]
  ) async throws {
    let encoder = JSONEncoder()
    
    try await client.withConnection { connection in
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
    client: ValkeyClient,
    ids: [User.ID]
  ) async throws {
    try await client.del(
      keys: ids.map { ValkeyKey($0.uuidString) }
    )
  }

  //MARK: DB

  func getUsersFromDB(
    request: Request,
    ids: [User.ID]
  ) async throws -> [User] {
    let users = ids.compactMap { id in
      request.application.storage[UsersStorageKey.self]?.users.withLock { $0[id] }
    }
    return users
  }

  func addUsersToDB(
    request: Request,
    newUsers: [NewUser]
  ) async throws -> [User] {
    let users: [User] = newUsers.map { user in
      let user = User(id: UUID(), name: user.name, birthDay: user.birthDay)
      return user
    }
    
    for user in users {
      request.application.storage[UsersStorageKey.self]?.users.withLock { $0[user.id] = user }
    }

    return users
  }

  func deleteUsersFromDB(
    request: Request,
    ids: [User.ID]
  ) async throws {
    for id in ids {
      request.application.storage[UsersStorageKey.self]?.users.withLock { $0[id] = nil }
    }
  }
}
