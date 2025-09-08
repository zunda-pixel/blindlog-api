import Foundation
import Hummingbird
import NIOFoundationCompat
import PostgresKit
import PostgresNIO
import Valkey

struct MeRouter<Context: RequestContext> {
  var cache: ValkeyClient
  var logger: Logger = Logger(label: "MeRouter")
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
  }

  //MARK: Routing

  func create(
    request: Request,
    context: some RequestContext
  ) async throws -> User {
    do {
      let newUser = try await request.decode(as: NewUser.self, context: context)

      // 1. Add to User to DB
      let addedUser = try await addUserToDatabase(
        request: request,
        newUser: newUser
      )

      // 2. Delete User from Cache
      try await deleteUserFromCache(
        id: addedUser.id
      )
      return addedUser
    } catch {
      logger.error(
        """
        Failed to save user
        Error: \(error)
        """
      )
      throw HTTPError(.internalServerError)
    }
  }

  func id(request: Request) -> UUID? {
    guard let idsQuery = request.uri.queryParameters["id"] else { return nil }

    return UUID(uuidString: String(idsQuery))
  }

  func show(
    request: Request
  ) async throws -> User {
    guard let id = id(request: request) else { throw HTTPError(.badRequest) }

    do {
      // 1. Get User from Cache and Update Expiration if exits
      let cacheUser = try await getUserFromCacheAndUpdateExpiration(
        id: id
      )

      if let cacheUser {
        return cacheUser
      }

      // 2. Get User from DB that is not in Cache
      let dbUser: User? = try await getUserFromDatabase(
        request: request,
        id: id
      )

      guard let dbUser else { throw HTTPError(.notFound) }

      // 3. Set New User to Cache
      try await addUserToCache(
        user: dbUser
      )
      return dbUser
    } catch {
      logger.error(
        """
        Failed to fetch user: \(id))
        Error: \(error)
        """
      )
      throw HTTPError(.internalServerError)
    }
  }

  //MARK: Cache

  func getUserFromCacheAndUpdateExpiration(
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

  func addUserToCache(
    user: User
  ) async throws {
    try await cache.set(
      ValkeyKey("user:\(user.id.uuidString)"),
      value: try JSONEncoder().encode(user),
      expiration: .seconds(60 * 10)  // 10 minutes
    )
  }

  func deleteUserFromCache(
    id: User.ID
  ) async throws {
    try await cache.del(keys: [ValkeyKey("user:\(id.uuidString)")])
  }

  //MARK: Database

  func getUserFromDatabase(
    request: Request,
    id: User.ID
  ) async throws -> User? {
    let query: PostgresQuery = "SELECT id, name FROM users where id = ANY(\(id)) LIMIT 1"

    let rows = try await database.query(query).collect()

    if let row = rows.first {
      return try row.sql().decode(model: User.self, with: SQLRowDecoder())
    } else {
      return nil
    }
  }

  func addUserToDatabase(
    request: Request,
    newUser: NewUser
  ) async throws -> User {
    return try await database.withConnection { connection in
      let query: PostgresQuery = """
          INSERT INTO users (id, name)
          VALUES (uuidv7(), \(newUser.name))
          RETURNING *
        """
      let result = try await connection.query(query, logger: Logger(label: "Database INSERT"))
      do {
        let user = try await result.collect().first?.sql().decode(
          model: User.self,
          with: SQLRowDecoder()
        )
        
        guard let user else {
          self.logger.error("Failed to insert user")
          try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
          throw HTTPError(.internalServerError)
        }
        
        return user
      } catch {
        self.logger.error("Failed to insert user")
        try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
        throw HTTPError(.internalServerError)
      }
    }
  }
}
