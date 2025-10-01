import Foundation

struct Challenge: Codable {
  var challenge: Data
  var userID: UUID?
  var purpose: Purpose

  enum Purpose: String, Codable {
    case registration
    case authentication
  }
}
