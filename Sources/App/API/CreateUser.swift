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
      AppRequestContext.current?.logger.appError(
        eventName: "user.create_failed",
        "Failed to persist user",
        metadata: AppLogMetadata.userID(user.id).merging([
          "db.operation": .string("insert")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    let userToken: Components.Schemas.UserToken
    do {
      userToken = try await generateUserToken(userID: user.id)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "auth.token.issue_failed",
        "Failed to sign user tokens",
        metadata: AppLogMetadata.userID(user.id),
        error: error
      )
      return .badRequest
    }
    return .ok(.init(body: .json(userToken)))
  }
}
