import Foundation

struct TOTPEmailAuthentication: Codable {
  var challenge: Data
  var email: String
  var hashedPassword: Data
}
