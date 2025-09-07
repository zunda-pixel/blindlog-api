import Foundation

struct NewUser: Codable, Hashable {
  var name: String
  var birthDay: Date?
}

struct User: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  var birthDay: Date?
}
