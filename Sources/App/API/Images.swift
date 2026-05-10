import Foundation
import Hummingbird
import PostgresNIO
import Records
import SQLKit
import UUIDV7

extension API {
  func createImageUploadURL(
    _ input: Operations.CreateImageUploadURL.Input
  ) async throws -> Operations.CreateImageUploadURL.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    let upload: CloudflareDirectUpload
    do {
      upload = try await cloudflareImagesClient.createDirectUploadURL(userID: userID)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "image.upload_url_create_failed",
        "Failed to create Cloudflare Images upload URL",
        metadata: ["cloudflare.operation": .string("images.direct_upload")],
        error: error
      )
      return .badRequest
    }

    return .ok(.init(body: .json(.init(upload))))
  }

  func createImage(
    _ input: Operations.CreateImage.Input
  ) async throws -> Operations.CreateImage.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    guard case .json(let bodyData) = input.body else {
      return .badRequest
    }

    let savedImage: ImageRecord?
    do {
      let existingImage = try await database.read { db in
        try await ImageRecord
          .where({ $0.cloudflareImageID.eq(bodyData.imageID) })
          .limit(1)
          .fetchOne(db)
      }
      if let existingImage {
        guard existingImage.userID == userID else {
          return .badRequest
        }
        return .ok(.init(body: .json(.init(existingImage))))
      }

      try await cloudflareImagesClient.verifyUploadedImage(id: bodyData.imageID, userID: userID)

      savedImage = try await database.write { db in
        let image = ImageRecord(
          id: UUID(uuidString: UUID.uuidV7String())!,
          userID: userID,
          cloudflareImageID: bodyData.imageID,
          createdAt: Date()
        )

        try await ImageRecord.insert {
          image
        } onConflict: {
          $0.cloudflareImageID
        }
        .execute(db)

        return
          try await ImageRecord
          .where({ $0.cloudflareImageID.eq(bodyData.imageID) })
          .limit(1)
          .fetchOne(db)
      }
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "image.create_failed",
        "Failed to verify or persist image",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("insert"),
          "image.id": .string(bodyData.imageID),
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    guard let savedImage else {
      return .badRequest
    }
    guard savedImage.userID == userID else {
      return .badRequest
    }

    return .ok(.init(body: .json(.init(savedImage))))
  }
}

extension Components.Schemas.CreateImageUploadURLResponse {
  init(_ upload: CloudflareDirectUpload) {
    self.init(
      imageID: upload.id,
      uploadURL: upload.uploadURL.absoluteString
    )
  }
}

extension Components.Schemas.Image {
  init(_ image: ImageRecord) {
    self.init(
      id: image.id.uuidString,
      imageID: image.cloudflareImageID,
      createdAt: image.createdAt.timeIntervalSinceReferenceDate
    )
  }
}
