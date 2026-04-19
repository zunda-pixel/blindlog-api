import Foundation
import StructuredQueriesPostgres

@Table("passkey_credentials")
struct PasskeyCredential {
  var id: String
  @Column("user_id") var userID: UUID
  @Column("public_key") var publicKeyBase64: String
  @Column("sign_count") var signCount: Int64
}

extension PasskeyCredential {
  init(id: String, userID: UUID, publicKey: Data, signCount: Int64) {
    self.id = id
    self.userID = userID
    self.publicKeyBase64 = publicKey.base64EncodedString()
    self.signCount = signCount
  }

  var publicKey: Data? {
    Data(base64Encoded: publicKeyBase64)
  }
}
