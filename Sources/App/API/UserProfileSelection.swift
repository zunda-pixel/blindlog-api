import Foundation
import PostgreSQL
import SQL
import SQL_Foundation_Integration
import SQL_Macros

@Selection
struct UserProfile: Codable {
  var id: UUID
  var userID: UUID?
  var name: String?
  var cloudflareImageID: String?
  var createdAt: Date?

  init(_ profile: UserProfileRecord, cloudflareImageID: String?) {
    self.id = profile.id
    self.userID = profile.userID
    self.name = profile.name
    self.cloudflareImageID = cloudflareImageID
    self.createdAt = profile.createdAt
  }
}
