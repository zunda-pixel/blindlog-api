import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit

extension API {
  func createUser(
    _ input: Operations.createUser.Input
  ) async throws -> Operations.createUser.Output {
    let user = User(id: UUID())

    try await database.write { db in
      try await User.insert { user }.execute(db)
    }

    let tokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)),  // 1 hour
      userName: user.id.uuidString
    )

    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)),  // 1 year
      userName: user.id.uuidString
    )

    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)

    return .ok(
      .init(
        body: .json(
          .init(
            id: user.id.uuidString,
            token: token,
            refreshToken: refreshToken
          ))))
  }
}
