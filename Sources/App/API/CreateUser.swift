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
    guard let ipAddressCount = RateLimitContext.ipAddressAccessCount, ipAddressCount < 30 else {
      throw HTTPError(.tooManyRequests)
    }
    let user = User(id: UUID(uuidString: UUID.uuidV7String())!)

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
      return .badRequest
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
      return .badRequest
    }
    return .ok(.init(body: .json(userToken)))
  }
}
