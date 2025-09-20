import Foundation
import PostgresNIO
import Hummingbird
import SQLKit

extension API {
  func createUser(
    _ input: Operations.createUser.Input
  ) async throws -> Operations.createUser.Output {
    let user = try await addUserToDatabase()
    
    let tokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)), // 1 hour
      userName: user.id.uuidString
    )
    
    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)), // 1 year
      userName: user.id.uuidString
    )
    
    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)

    return .ok(.init(body: .json(.init(
      id: user.id.uuidString,
      token: token,
      refreshToken: refreshToken
    ))))
  }
  
  func addUserToDatabase() async throws -> User {
    return try await database.withConnection { connection in
      do {
        // 1. Insert into users
        let result = try await connection.query(
          """
            INSERT INTO users (id)
            VALUES (gen_random_uuid())
            RETURNING *
          """,
          logger: Logger(label: "Database INSERT")
        )
        
        let user = try await result.collect().first?.sql().decode(
          model: User.self,
          with: SQLRowDecoder()
        )
        
        guard let user else {
//          self.logger.error("Failed to insert user. Not found user")
          try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
          throw HTTPError(.internalServerError)
        }
        return user
      } catch {
//        self.logger.error(
//          """
//            Failed to insert user
//            Error: \(String(reflecting: error))
//          """)
        try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
        throw HTTPError(.internalServerError)
      }
    }
  }
}
