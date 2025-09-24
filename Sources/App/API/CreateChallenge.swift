import Foundation
import Hummingbird
import WebAuthn

extension API {
  func generateChallenge(
    _ input: Operations.generateChallenge.Input
  ) async throws -> Operations.generateChallenge.Output {
    // 1. Generate Challenge
    let userID = BearerAuthenticateUser.current?.userID

    let challenge: [UInt8] =
      if let userID {
        // SignUp
        webAuthn.beginRegistration(
          user: .init(
            id: Array(Data(userID.uuidString.utf8)),
            name: userID.uuidString,
            displayName: userID.uuidString
          )
        ).challenge
      } else {
        // SignIn
        webAuthn.beginAuthentication().challenge
      }

    // 2. Save Challenge to DB with expired date
    let challengeRow = Challenge(
      challenge: Data(challenge),
      expiredDate: Date(timeIntervalSinceNow: 10 * 60),  // 10 minutes
      userID: userID,
      purpose: userID == nil ? .authentication : .registration
    )
    try await database.write { db in
      try await Challenge.insert {
        challengeRow
      }.execute(db)
    }

    return .ok(.init(body: .json(.init(challenge))))
  }
}
