import Algorithms
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import UUIDV7

extension API {
  func getUserProfile(
    _ input: Operations.GetUserProfile.Input
  ) async throws -> Operations.GetUserProfile.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    let profile: UserProfileRecord?
    do {
      profile = try await latestUserProfile(userID: userID)
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

    guard let profile else {
      return .notFound
    }

    return .ok(.init(body: .json(.init(profile))))
  }

  func createUserProfile(
    _ input: Operations.CreateUserProfile.Input
  ) async throws -> Operations.CreateUserProfile.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    guard case .json(let bodyData) = input.body else {
      return .badRequest
    }

    let name = String(bodyData.name.trimming(while: \.isWhitespace))
    guard (1...100).contains(name.count) else {
      return .badRequest
    }

    let imageID: UUID?
    if let requestedImageID = bodyData.imageID {
      guard let parsedImageID = UUID(uuidString: requestedImageID) else {
        return .badRequest
      }

      do {
        guard try await imageBelongsToUser(imageID: parsedImageID, userID: userID) else {
          return .badRequest
        }
      } catch {
        AppRequestContext.current?.logger.appError(
          eventName: "user.profile_image_read_failed",
          "Failed to fetch user profile image",
          metadata: AppLogMetadata.userID(userID).merging([
            "db.operation": .string("select"),
            "image.id": .string(requestedImageID),
          ]) { _, new in new },
          error: error
        )
        return .badRequest
      }

      imageID = parsedImageID
    } else {
      imageID = nil
    }

    let profile = UserProfileRecord(
      id: UUID(uuidString: UUID.uuidV7String())!,
      userID: userID,
      imageID: imageID,
      name: name,
      createdAt: Date()
    )

    do {
      try await database.write { db in
        try await UserProfileRecord.insert { profile }.execute(db)
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.profile_create_failed",
        "Failed to persist user profile",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("insert")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(profile))))
  }

  fileprivate func latestUserProfile(userID: UUID) async throws -> UserProfileRecord? {
    try await database.read { db in
      try await UserProfileRecord
        .where { $0.userID.eq(userID) }
        .order { profile in
          (profile.createdAt.desc(), profile.id.desc())
        }
        .limit(1)
        .fetchOne(db)
    }
  }

  fileprivate func imageBelongsToUser(imageID: UUID, userID: UUID) async throws -> Bool {
    try await database.read { db in
      try await ImageRecord
        .where {
          $0.id.eq(imageID)
            .and($0.userID.eq(userID))
        }
        .limit(1)
        .fetchOne(db) != nil
    }
  }
}

extension Components.Schemas.UserProfile {
  init(_ profile: UserProfileRecord) {
    self.init(
      id: profile.id.uuidString,
      userID: profile.userID.uuidString,
      imageID: profile.imageID?.uuidString,
      name: profile.name,
      createdAt: profile.createdAt.timeIntervalSinceReferenceDate
    )
  }
}
