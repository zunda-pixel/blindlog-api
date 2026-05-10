import AsyncHTTPClient
import Foundation
import Images

protocol CloudflareImagesClientProtocol: Sendable {
  func createDirectUploadURL(userID: UUID) async throws -> CloudflareDirectUpload
  func verifyUploadedImage(id: String, userID: UUID) async throws
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
    let image = try await client.image(id: id)
    guard image.metadatas?["userID"] == userID.uuidString else {
      throw CloudflareImageVerificationError()
    }
    guard !image.requireSignedURLs else {
      throw CloudflareImageVerificationError()
    }
  }
}

struct CloudflareImageVerificationError: Error {}
