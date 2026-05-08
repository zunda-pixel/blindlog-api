import Foundation
import Records

@Table("user_profiles")
struct UserProfileRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("user_id") var userID: UUID
  var name: String
  @Column("created_at") var createdAt: Date
}
