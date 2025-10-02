import Algorithms
import Crypto
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres

extension API {
  func confirmEmail(
    _ input: Operations.ConfirmEmail.Input
  ) async throws -> Operations.ConfirmEmail.Output {
    guard let userID = User.currentUserID else { return .unauthorized }
    let email = normalizeEmail(input.query.email)
    let hashedPassword = Data(SHA256.hash(data: Data(input.query.password.utf8)))
    // 1. Verify totp
    do {
      let row = try await database.write { db in
        try await TOTP
          .delete()
          .where {
            $0.userID.eq(userID)
              .and($0.email.eq(email))
              .and($0.password.eq(hashedPassword))
          }
          .returning(\.self)
          .fetchOne(db)
      }

      guard row != nil else {
        return .badRequest(.init())
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
      return .badRequest(.init())
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
      return .badRequest(.init())
    }

    return .ok
  }
}
