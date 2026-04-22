import Foundation
import Hummingbird
import JWTKit
import Logging
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
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to persist user",
        metadata: Logger.errorMetadata(error, [
          "user.id": .stringConvertible(user.id),
        ])
      )
      return .badRequest
    }

    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(userID: user.id)
    } catch {
      AppRequestContext.current?.logger.log(
        level: .error,
        "Failed to sign user tokens",
        metadata: Logger.errorMetadata(error, [
          "user.id": .stringConvertible(user.id),
        ])
      )
      return .badRequest
    }
    return .ok(.init(body: .json(userToken)))
  }
}
