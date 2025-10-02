import Foundation
import Records

@Table("totps")
struct TOTP: Codable, Hashable {
  var password: Data
  var userID: User.ID
  var email: String
}
