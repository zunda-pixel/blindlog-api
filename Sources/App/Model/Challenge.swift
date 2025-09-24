import Foundation
import Records

@Table("challenges")
struct Challenge {
  var challenge: Data
  @Column("expired_date") var expiredDate: Date
  @Column("user_id") var userID: UUID
  @Column("purpose") var purpose: Purpose
  
  enum Purpose: String, PostgresCodable, QueryBindable {
    case registration
    case authentication
  }
}
