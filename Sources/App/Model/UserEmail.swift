import Foundation
import Records

@Table("user_email")
struct UserEmail: Codable, Hashable {
  var userID: UUID
  var email: String
}
