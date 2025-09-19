import Foundation
import Hummingbird
import PostgresNIO

struct NewUser: Codable, Hashable {
  var name: String
}

struct User: Codable, Identifiable, Hashable, ResponseGenerator {
  var id: UUID
  var token: String
  var refreshToken: String
  var email: String?

  func response(
    from request: HummingbirdCore.Request,
    context: some Hummingbird.RequestContext
  ) throws -> HummingbirdCore.Response {
    try context.responseEncoder.encode(self, from: request, context: context)
  }
}
