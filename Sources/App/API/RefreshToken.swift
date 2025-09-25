import Foundation
import Hummingbird
import JWTKit
import PostgresNIO
import SQLKit
import Valkey

extension API {
  func generateUserToken(
    userID: UUID
  ) async throws -> (token: String, refreshToken: String) {
    let tokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)),  // 1 hour
      userName: userID.uuidString
    )

    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)),  // 1 year
      userName: userID.uuidString
    )

    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)

    return (token, refreshToken)
  }

  func refreshToken(
    _ input: Operations.refreshToken.Input
  ) async throws -> Operations.refreshToken.Output {
    guard case .json(let body) = input.body else {
      throw HTTPError(.unauthorized)
    }

    let payload = try await jwtKeyCollection.verify(body.refreshToken, as: JWTPayloadData.self)

    guard let userID = UUID(uuidString: payload.subject.value) else {
      //      context.logger.debug("Invalid JWT subject \(payload.subject.value)")
      throw HTTPError(.unauthorized)
    }
    // verify expiration is not over.
    guard payload.expiration.value > Date() else {
      //      context.logger.debug("Token expired")
      throw HTTPError(.unauthorized)
    }

    let (token, refreshToken) = try await generateUserToken(userID: userID)

    return .ok(
      .init(
        body: .json(
          .init(
            id: userID.uuidString,
            token: token,
            refreshToken: refreshToken
          ))))
  }
}
