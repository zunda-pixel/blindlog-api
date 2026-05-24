import AsyncHTTPClient
import Foundation
import Images

protocol CloudflareImagesClientProtocol: Sendable {
  func createDirectUploadURL(userID: UUID) async throws -> CloudflareDirectUpload
  func verifyUploadedImage(id: String, userID: UUID) async throws
  func imageURL(id: String, userID: UUID) async throws -> URL
}

struct CloudflareDirectUpload: Sendable, Hashable {
  var id: String
  var uploadURL: URL
}

struct CloudflareImagesClient: CloudflareImagesClientProtocol {
  var client: Images.Client<AsyncHTTPClient.HTTPClient>

  func createDirectUploadURL(userID: UUID) async throws -> CloudflareDirectUpload {
    let result = try await client.createAuthenticatedUploadURL(
      metadatas: ["userID": userID.uuidString],
      requireSignedURLs: false
    )
    return CloudflareDirectUpload(id: result.id, uploadURL: result.uploadURL)
  }

  func verifyUploadedImage(id: String, userID: UUID) async throws {
    _ = try await uploadedImage(id: id, userID: userID)
  }

  func imageURL(id: String, userID: UUID) async throws -> URL {
    let image = try await uploadedImage(id: id, userID: userID)
    guard let url = image.variants.first else {
      throw CloudflareImageVerificationError.missingVariantURL
    }
    return url
  }

  private func uploadedImage(id: String, userID: UUID) async throws -> Image {
    let image = try await client.image(id: id)
    let imageUserID = image.metadatas?["userID"]
    guard imageUserID == userID.uuidString else {
      throw CloudflareImageVerificationError.userIDMetadataMismatch(
        expected: userID.uuidString,
        actual: imageUserID
      )
    }
    guard !image.requireSignedURLs else {
      throw CloudflareImageVerificationError.signedURLsRequired
    }
    return image
  }
}

enum CloudflareImageVerificationError: Error, CustomStringConvertible {
  case userIDMetadataMismatch(expected: String, actual: String?)
  case signedURLsRequired
  case missingVariantURL

  var description: String {
    switch self {
    case .userIDMetadataMismatch(let expected, let actual):
      "Cloudflare image userID metadata mismatch. expected=\(expected), actual=\(actual ?? "nil")"
    case .signedURLsRequired:
      "Cloudflare image requires signed URLs."
    case .missingVariantURL:
      "Cloudflare image has no variant URL."
    }
  }
}
