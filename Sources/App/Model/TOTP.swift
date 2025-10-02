import Foundation
import Records

@Table("totps")
struct TOTP: Codable, Hashable {
  var password: String
  var messageID: String
  var userID: User.ID
  var email: String
}
