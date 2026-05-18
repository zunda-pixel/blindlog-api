import Algorithms
import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import UUIDV7
import Valkey

extension API {
  func getUserProfile(
    _ input: Operations.GetUserProfile.Input
  ) async throws -> Operations.GetUserProfile.Output {
    guard UserTokenContext.currentUserID != nil else {
      return .unauthorized
    }
    guard let userID = UUID(uuidString: input.path.userId) else {
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

    guard let profile else { return .notFound }

    return .ok(.init(body: .json(profile)))
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
    let cloudflareImageID: String?
    if let requestedImageID = bodyData.imageID {
      guard let parsedImageID = UUID(uuidString: requestedImageID) else {
        return .badRequest
      }

      do {
        guard
          let imageCloudflareID = try await userImageCloudflareID(
            imageID: parsedImageID,
            userID: userID
          )
        else {
          return .badRequest
        }
        cloudflareImageID = imageCloudflareID
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
      cloudflareImageID = nil
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

    do {
      let profileForCache = UserProfile(profile, cloudflareImageID: cloudflareImageID)
      do {
        try await replaceCachedLatestProfile(profileForCache, userID: userID)
      } catch {
        AppRequestContext.current?.logger.appLog(
          level: .warning,
          eventName: "user.profile_cache_write_failed",
          "Failed to write latest user profile to cache",
          metadata: AppLogMetadata.userID(userID).merging([
            "cache.operation": .string("set")
          ]) { _, new in new },
          error: error
        )
      }

      return .ok(
        .init(
          body: .json(
            try await userProfileResponse(
              profileForCache,
              userID: userID
            )
          )
        )
      )
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.profile_image_url_read_failed",
        "Failed to fetch user profile image URL",
        metadata: AppLogMetadata.userID(userID).merging([
          "cloudflare.operation": .string("images.image")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }
  }

  func getProfile(userID: UUID) async throws -> Components.Schemas.UserProfile? {
    do {
      if let cachedProfile = try await cachedLatestProfile(userID: userID) {
        return try await userProfileResponse(cachedProfile, userID: userID)
      }
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "user.profile_cache_read_failed",
        "Failed to fetch latest user profile from cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("getex")
        ]) { _, new in new },
        error: error
      )
    }

    let profile = try await database.read { db in
      try await UserProfileRecord
        .leftJoin(ImageRecord.all) { profile, image in
          profile.imageID.eq(image.id)
        }
        .where { profile, _ in profile.userID.eq(userID) }
        .order { profile, _ in
          (profile.createdAt.desc(), profile.id.desc())
        }
        .select { profile, image in
          UserProfile.Columns(
            id: profile.id,
            userID: SQLQueryExpression<UUID?>(profile.userID.queryFragment),
            name: SQLQueryExpression<String?>(profile.name.queryFragment),
            cloudflareImageID: image.cloudflareImageID,
            createdAt: SQLQueryExpression<Date?>(profile.createdAt.queryFragment)
          )
        }
        .limit(1)
        .fetchOne(db)
    }

    guard let profile else { return nil }

    do {
      try await cacheLatestProfile(profile, userID: userID)
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "user.profile_cache_write_failed",
        "Failed to write latest user profile to cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("set")
        ]) { _, new in new },
        error: error
      )
    }

    return try await userProfileResponse(profile, userID: userID)
  }

  fileprivate func userImageCloudflareID(imageID: UUID, userID: UUID) async throws -> String? {
    do {
      if let cachedImage = try await cachedImage(id: imageID) {
        guard cachedImage.userID == userID else { return nil }
        return cachedImage.cloudflareImageID
      }
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "image.cache_read_failed",
        "Failed to fetch image from cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("getex"),
          "image.uuid": .string(imageID.uuidString),
        ]) { _, new in new },
        error: error
      )
    }

    let image = try await database.read { db in
      try await ImageRecord
        .where {
          $0.id.eq(imageID)
            .and($0.userID.eq(userID))
        }
        .limit(1)
        .fetchOne(db)
    }
    guard let image else { return nil }

    do {
      try await cacheImage(image)
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "image.cache_write_failed",
        "Failed to write image to cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("set"),
          "image.uuid": .string(imageID.uuidString),
        ]) { _, new in new },
        error: error
      )
    }

    return image.cloudflareImageID
  }

  fileprivate func userProfileResponse(
    _ profile: UserProfile,
    userID: UUID
  ) async throws -> Components.Schemas.UserProfile {
    let imageURL: String?
    if let cloudflareImageID = profile.cloudflareImageID {
      imageURL = try await profileImageURL(cloudflareImageID: cloudflareImageID, userID: userID)
    } else {
      imageURL = nil
    }

    return .init(profile, imageURL: imageURL)
  }

  fileprivate func cachedLatestProfile(userID: UUID) async throws -> UserProfile? {
    let profileData = try await cache.getex(
      latestUserProfileCacheKey(userID),
      expiration: .seconds(60 * 10)
    )
    guard let profileData else { return nil }
    return try JSONDecoder().decode(UserProfile.self, from: Data(profileData))
  }

  fileprivate func cacheLatestProfile(_ profile: UserProfile, userID: UUID) async throws {
    try await cache.set(
      latestUserProfileCacheKey(userID),
      value: try JSONEncoder().encode(profile),
      expiration: .seconds(60 * 10)
    )
  }

  fileprivate func replaceCachedLatestProfile(_ profile: UserProfile, userID: UUID) async throws {
    try await cache.del(keys: [latestUserProfileCacheKey(userID)])
    try await cacheLatestProfile(profile, userID: userID)
  }

  fileprivate func profileImageURL(cloudflareImageID: String, userID: UUID) async throws -> String {
    let key = imageURLCacheKey(userID: userID, cloudflareImageID: cloudflareImageID)
    do {
      if let imageURLData = try await cache.getex(key, expiration: .seconds(60 * 10)) {
        return String(decoding: Data(imageURLData), as: UTF8.self)
      }
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "image.url_cache_read_failed",
        "Failed to fetch image URL from cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("getex"),
          "image.id": .string(cloudflareImageID),
        ]) { _, new in new },
        error: error
      )
    }

    let imageURL = try await cloudflareImagesClient.imageURL(
      id: cloudflareImageID,
      userID: userID
    ).absoluteString
    do {
      try await cache.set(
        key,
        value: Data(imageURL.utf8),
        expiration: .seconds(60 * 10)
      )
    } catch {
      AppRequestContext.current?.logger.appLog(
        level: .warning,
        eventName: "image.url_cache_write_failed",
        "Failed to write image URL to cache",
        metadata: AppLogMetadata.userID(userID).merging([
          "cache.operation": .string("set"),
          "image.id": .string(cloudflareImageID),
        ]) { _, new in new },
        error: error
      )
    }
    return imageURL
  }

  fileprivate func latestUserProfileCacheKey(_ userID: UUID) -> ValkeyKey {
    ValkeyKey("user_profile:latest:\(userID.uuidString)")
  }

  fileprivate func imageURLCacheKey(userID: UUID, cloudflareImageID: String) -> ValkeyKey {
    ValkeyKey("image_url:\(userID.uuidString):\(cloudflareImageID)")
  }
}

extension Components.Schemas.UserProfile {
  fileprivate init(_ profile: UserProfile, imageURL: String?) {
    self.init(
      id: profile.id.uuidString,
      userID: profile.userID!.uuidString,
      name: profile.name!,
      imageURL: imageURL,
      createdAt: profile.createdAt!.timeIntervalSinceReferenceDate
    )
  }
}
