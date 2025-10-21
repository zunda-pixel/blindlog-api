import Foundation

struct OTPEmailAuthentication: Codable {
  var challenge: Data
  var email: String
  var hashedPassword: Data
}
