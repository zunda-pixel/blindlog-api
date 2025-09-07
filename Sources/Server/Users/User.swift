import Foundation
import PostgresNIO

struct NewUser: Codable, Hashable {
  var name: String
}

struct User: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
}
