import Foundation
import Records
import Tagged

@Table("users")
struct User: Codable, Identifiable, Hashable {
  var id: UUID
}

struct UserToken: Codable, Identifiable, Hashable {
  var id: UUID
  var token: String
  var refreshToken: String
}
