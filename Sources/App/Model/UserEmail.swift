import Foundation
import Records

@Table("user_email")
struct UserEmail: Codable, Hashable {
  @Column("user_id") var userID: UUID
  var email: String
}
