import Foundation
import Hummingbird
import WebAuthn

extension API {
  func generateChallenge(
    _ input: Operations.generateChallenge.Input
  ) async throws -> Operations.generateChallenge.Output {
    // 1. Generate Challenge
    let challenge: [UInt8] = if let userID = BearerAuthenticateUser.current?.userID {
      // SignUp
      webAuthn.beginRegistration(
        user: .init(
          id: Array(Data(userID.uuidString.utf8)),
          name: userID.uuidString,
          displayName: userID.uuidString
        )
      ).challenge
    } else {
      // SingIn
      webAuthn.beginAuthentication().challenge
    }

    let expiredDate = Date(timeIntervalSinceNow: 10 * 60)  // 10 minutes

    // 2. Save Challenge to DB with expired date

    let challengeString = Data(challenge).base64EncodedString()

    try await database.query(
      """
        INSERT INTO user_challenge challenge, expired_date)
        VALUES(\(challengeString), \(expiredDate))
      """
    )

    return .ok(.init(body: .json(.init(challenge))))
  }
}
