import Foundation
import Hummingbird
import JWTKit
import PostgresNIO
import Records
import SQLKit
import UUIDV7

extension API {
  func createUser(
    _ input: Operations.CreateUser.Input
  ) async throws -> Operations.CreateUser.Output {
    let user = User(id: UUIDV7().rawValue)

    do {
      try await database.write { db in
        try await User.insert { user }.execute(db)
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to persist user",
        metadata: [
          "user": .string(user.id.uuidString),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }

    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(userID: user.id)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to sign user tokens",
        metadata: [
          "user": .string(String(describing: user)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }
    return .ok(.init(body: .json(userToken)))
  }
}
