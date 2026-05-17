import Foundation
import Records

@Selection
struct UserProfile: Codable {
  var id: UUID
  var userID: UUID?
  var email: String?
  var name: String?
  var cloudflareImageID: String?
  var createdAt: Date?

  init(_ profile: UserProfileRecord, cloudflareImageID: String?) {
    self.id = profile.id
    self.userID = profile.userID
    self.email = nil
    self.name = profile.name
    self.cloudflareImageID = cloudflareImageID
    self.createdAt = profile.createdAt
  }
}
