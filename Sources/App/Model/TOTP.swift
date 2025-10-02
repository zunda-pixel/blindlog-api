import Foundation
import Records

@Table("totps")
struct TOTP: Codable, Hashable {
  var password: Data
  @Column("user_id") var userID: User.ID
  var email: String
}
