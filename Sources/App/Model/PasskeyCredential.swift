import Foundation
import StructuredQueriesPostgres

@Table("passkey_credentials")
struct PasskeyCredential {
  var id: String
  @Column("user_id") var userID: UUID
  @Column("public_key") var publicKey: Data
  @Column("sign_count") var signCount: Int64
}
