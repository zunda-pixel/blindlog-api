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
    let expiredDate = Date(timeIntervalSinceNow: 10 * 60)  // 10 minutes
    let purpose: Challenge.Purpose = userID == nil ? .authentication : .registration
    try await database.query(
      """
        INSERT INTO challenges (challenge, expired_date, user_id, purpose)
        VALUES(\(Data(challenge)), \(expiredDate), \(userID), \(purpose))
      """
    )

    return .ok(.init(body: .json(.init(challenge))))
  }
}
