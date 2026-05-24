import Foundation
import Hummingbird
import Logging
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres

extension API {
  func getMe(_ input: Operations.GetMe.Input) async throws -> Operations.GetMe.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    let emails: [UserEmail]
    do {
      emails = try await registeredEmails(userID: userID)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.email.list_failed",
        "Failed to fetch registered emails",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("select")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    let profile: Components.Schemas.UserProfile?
    do {
      profile = try await getProfile(userID: userID)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.profile_read_failed",
        "Failed to fetch user profile",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("select")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(userID: userID, profile: profile, emails: emails))))
  }

  fileprivate func registeredEmails(userID: UUID) async throws -> [UserEmail] {
    try await database.read { db in
      try await UserEmail
        .where { $0.userID.eq(userID) }
        .order { ($0.createdAt.asc(), $0.email.asc()) }
        .fetchAll(db)
    }
  }
}

extension Components.Schemas.Me {
  fileprivate init(userID: UUID, profile: Components.Schemas.UserProfile?, emails: [UserEmail]) {
    self.init(
      userID: userID.uuidString,
      userProfile: profile.map { .init($0) },
      emails: emails.map { .init($0) }
    )
  }
}

extension Components.Schemas.MeUserProfile {
  fileprivate init(_ profile: Components.Schemas.UserProfile) {
    self.init(
      name: profile.name,
      imageURL: profile.imageURL,
      createdAt: profile.createdAt
    )
  }
}

extension Components.Schemas.Email {
  fileprivate init(_ email: UserEmail) {
    self.init(
      email: email.email,
      createdAt: email.createdAt.timeIntervalSinceReferenceDate
    )
  }
}
