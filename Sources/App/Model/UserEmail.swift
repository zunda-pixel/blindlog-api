import Foundation
import PostgreSQL
import SQL
import SQL_Foundation_Integration
import SQL_Macros

@Table("user_email")
struct UserEmail: Codable, Hashable {
  @Column("user_id") var userID: UUID
  var email: String
  @Column("created_at") var createdAt: Date
}
