import Foundation
import PostgreSQL
import SQL
import SQL_Foundation_Integration
import SQL_Macros

@Table("user_profiles")
struct UserProfileRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("user_id") var userID: UUID
  @Column("image_id") var imageID: UUID?
  var name: String
  @Column("created_at") var createdAt: Date
}
