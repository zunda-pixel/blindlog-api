import Algorithms
import Crypto
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import Valkey

extension API {
  func confirmEmail(
    _ input: Operations.ConfirmEmail.Input
  ) async throws -> Operations.ConfirmEmail.Output {
    guard let userID = User.currentUserID else { return .unauthorized }
    let email = normalizeEmail(input.query.email)
    let hashedPassword = Data(SHA256.hash(data: Data(input.query.password.utf8)))
    // 1. Verify totp
    do {
      let totpData = try await cache.get(ValkeyKey("TOTPEmailRegistration:\(userID.uuidString)"))
      guard let totpData else {
        return .badRequest
      }
      
      let totp = try JSONDecoder().decode(TOTPEmailRegistration.self, from: totpData)

      guard totp.userID == userID && totp.email == email else {
        return .badRequest
      }

      guard totp.hashedPassword == hashedPassword else {
        return .unauthorized
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to verify totp",
        metadata: [
          "userID": .string(userID.uuidString),
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    // 2. Save email to db
    do {
      try await database.write { db in
        try await UserEmail.insert {
          UserEmail(
            userID: userID,
            email: email
          )
        }.execute(db)
      }
    } catch {
      BasicRequestContext.current?.logger.log(
        level: .error,
        "Failed to save user email to db",
        metadata: [
          "userID": .string(userID.uuidString),
          "email": .string(email),
          "error": .string(String(describing: error)),
        ]
      )
      return .badRequest
    }

    return .ok
  }
}
