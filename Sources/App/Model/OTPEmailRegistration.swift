import Foundation

struct OTPEmailRegistration: Codable, Hashable {
  var hashedPassword: Data
  var userID: User.ID
  var email: String
}
