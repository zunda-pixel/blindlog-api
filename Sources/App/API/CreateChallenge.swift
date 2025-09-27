import Foundation
import Hummingbird
import OpenAPIRuntime
import Records
import StructuredQueriesPostgresCore
import WebAuthn

extension API {
  func createChallenge(
    _ input: Operations.CreateChallenge.Input
  ) async throws -> Operations.CreateChallenge.Output {
    // 1. Generate Challenge
    let userID = User.currentUserID

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
    try await database.write { db in
      try await Challenge.insert {
        Challenge(
          challenge: Data(challenge),
          expiredDate: Date(timeIntervalSinceNow: 10 * 60),  // 10 minutes
          userID: userID,
          purpose: userID == nil ? .authentication : .registration
        )
      }.execute(db)
    }

    return .ok(.init(body: .json(.init(challenge))))
  }
}
