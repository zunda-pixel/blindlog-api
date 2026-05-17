import Foundation
import Valkey

extension API {
  func cachedImage(id: UUID) async throws -> ImageRecord? {
    let imageData = try await cache.getex(
      imageIDCacheKey(id),
      expiration: .seconds(60 * 10)
    )
    guard let imageData else { return nil }
    return try JSONDecoder().decode(ImageRecord.self, from: Data(imageData))
  }

  func cachedImage(cloudflareImageID: String) async throws -> ImageRecord? {
    let imageData = try await cache.getex(
      imageCloudflareIDCacheKey(cloudflareImageID),
      expiration: .seconds(60 * 10)
    )
    guard let imageData else { return nil }
    return try JSONDecoder().decode(ImageRecord.self, from: Data(imageData))
  }

  func cacheImage(_ image: ImageRecord) async throws {
    let imageData = try JSONEncoder().encode(image)
    try await cache.set(
      imageIDCacheKey(image.id),
      value: imageData,
      expiration: .seconds(60 * 10)
    )
    try await cache.set(
      imageCloudflareIDCacheKey(image.cloudflareImageID),
      value: imageData,
      expiration: .seconds(60 * 10)
    )
  }

  func imageIDCacheKey(_ id: UUID) -> ValkeyKey {
    ValkeyKey("image:id:\(id.uuidString)")
  }

  func imageCloudflareIDCacheKey(_ cloudflareImageID: String) -> ValkeyKey {
    ValkeyKey("image:cloudflare_id:\(cloudflareImageID)")
  }
}
