import Foundation
import Hummingbird
import JWTKit
import PostgresNIO
import Records
import SQLKit

extension API {
  func createUser(
    _ input: Operations.CreateUser.Input
  ) async throws -> Operations.CreateUser.Output {
    let user = User(id: UUID())

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

    let tokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)),  // 1 hour
      tokenType: .token
    )

    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)),  // 1 year
      tokenType: .refreshToken
    )

    let token: String
    let refreshToken: String
    do {
      token = try await jwtKeyCollection.sign(tokenPayload)
      refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to sign user tokens",
        metadata: [
          "user": .string(String(describing: user)),
          "tokenPayload": .string(String(describing: tokenPayload)),
          "refreshTokenPayload": .string(String(describing: refreshTokenPayload)),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest(.init())
    }
    return .ok(
      .init(
        body: .json(
          .init(
            userID: user.id.uuidString,
            token: token,
            refreshToken: refreshToken
          ))))
  }
}
