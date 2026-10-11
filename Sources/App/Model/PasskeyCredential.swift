import Foundation
import ISO_9075_Foundation
import SQL
import SQL_Foundation_Integration
import SQL_Macros

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
