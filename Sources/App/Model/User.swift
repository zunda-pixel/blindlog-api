import Foundation
import PostgreSQL
import SQL
import SQL_Foundation_Integration
import SQL_Macros

@Table("users")
struct User: Codable, Identifiable, Hashable {
  var id: UUID
}
