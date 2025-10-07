import Foundation

struct TOTPEmailRegistration: Codable, Hashable {
  var hashedPassword: Data
  var userID: User.ID
  var email: String
}
