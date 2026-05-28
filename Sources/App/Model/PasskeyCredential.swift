import Foundation
import StructuredQueriesPostgres

@Table("passkey_credentials")
struct PasskeyCredential {
  var id: String
  @Column("user_id") var userID: UUID
  @Column("public_key") var publicKey: Data
}

@Table("passkey_credential_sign_counts")
struct PasskeyCredentialSignCount {
  var id: UUID
  @Column("passkey_credential_id") var passkeyCredentialID: String
  @Column("sign_count") var signCount: Int64
}
