import Foundation
import Hummingbird

extension API {
  func generateChallenge(
    _ input: Operations.generateChallenge.Input
  ) async throws -> Operations.generateChallenge.Output {
    guard let userID = BearerAuthenticateUser.current?.userID else {
      throw HTTPError(.badRequest)
    }

    // 1. Generate Challenge
    let options = webAuthn.beginRegistration(
      user: .init(
        id: Array(Data(userID.uuidString.utf8)),
        name: userID.uuidString,
        displayName: userID.uuidString
      )
    )

    let expiredDate = Date(timeIntervalSinceNow: 10 * 60)  // 10 minutes

    // 2. Save Challenge to DB with expired date

    let challengeString = Data(options.challenge).base64EncodedString()

    try await database.query(
      """
        INSERT INTO user_challenge (user_id, challenge, expired_date)
        VALUES(\(userID), \(challengeString), \(expiredDate))
      """
    )

    return .ok(.init(body: .json(challengeString)))
  }
}
