import Foundation
import Records

@Table("users")
struct User: Codable, Identifiable, Hashable {
  var id: UUID
}
