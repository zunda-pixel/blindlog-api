import Foundation
import Hummingbird
import NIOFoundationCompat
import PostgresKit
import PostgresNIO
import Valkey

struct SignupRouter<Context: RequestContext> {
  var cache: ValkeyClient
  var logger: Logger = Logger(label: "SignUpRouter")
  var database: PostgresClient

  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .post("signup") { request, context in
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
      guard let email = request.uri.queryParameters["email"] else { throw HTTPError(.badRequest) }

      // 1. Add to User to DB
      let addedUser = try await addUserToDatabase(
        request: request,
        email: String(email)
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
        Error: \(String(reflecting: error))
        """
      )
      throw HTTPError(.internalServerError)
    }
  }

  func deleteUserFromCache(
    id: User.ID
  ) async throws {
    try await cache.del(keys: [ValkeyKey("user:\(id.uuidString)")])
  }

  func addUserToDatabase(
    request: Request,
    email: String
  ) async throws -> User {
    return try await database.withConnection { connection in
      do {
        // 1. Insert into users
        let result = try await connection.query(
          """
            INSERT INTO users (id)
            VALUES (uuidv7())
            RETURNING *
          """,
          logger: Logger(label: "Database INSERT")
        )

        let user = try await result.collect().first?.sql().decode(
          model: User.self,
          with: SQLRowDecoder()
        )

        guard var user else {
          self.logger.error("Failed to insert user. Not found user")
          try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
          throw HTTPError(.internalServerError)
        }

        // 2. Insert into user_email
        try await connection.query(
          """
            INSERT INTO user_email (user_id, email)
            VALUES (\(user.id), \(email))
          """,
          logger: Logger(label: "Database INSERT")
        )

        user.email = email
        return user
      } catch {
        self.logger.error(
          """
            Failed to insert user
            Error: \(String(reflecting: error))
          """)
        try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
        throw HTTPError(.internalServerError)
      }
    }
  }
}

protocol AuthClient {
  func sendAuthorizationEmail(email: String) async throws
}
