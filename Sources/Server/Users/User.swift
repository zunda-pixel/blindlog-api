import Foundation
import Vapor

struct NewUser: Codable, Hashable, Content {
  var name: String
  var birthDay: Date?
}

struct User: Codable, Identifiable, Hashable, Content {
  var id: UUID
  var name: String
  var birthDay: Date?
}
