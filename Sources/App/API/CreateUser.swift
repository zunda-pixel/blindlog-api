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
      BasicRequestContext.current!.logger.info("""
        Failure to save a user
        user: \(user)
        Error: \(error)
        """)
      throw HTTPError(.badRequest)
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

    let token, refreshToken: String
    do {
      token = try await jwtKeyCollection.sign(tokenPayload)
      refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)
    } catch {
      BasicRequestContext.current!.logger.info("""
        Failure to update stored sign counter
        User: \(user)
        tokenPayload: \(tokenPayload)
        refreshTokenPayload: \(refreshTokenPayload)
        Error: \(error)
        """
      )
      throw HTTPError(.badRequest)
    }
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
