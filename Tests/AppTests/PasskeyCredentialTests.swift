import Foundation
import Testing

@testable import App

struct PasskeyCredentialTests {
  @Test
  func storesPublicKeyAsBase64Text() throws {
    let userID = UUID()
    let publicKey = Data([0xA5, 0x01, 0x02, 0x03])

    let credential = PasskeyCredential(
      id: "test-credential",
      userID: userID,
      publicKey: publicKey,
      signCount: 0
    )

    #expect(credential.userID == userID)
    #expect(credential.publicKeyBase64 == publicKey.base64EncodedString())
    #expect(try #require(credential.publicKey) == publicKey)
  }

  @Test
  func invalidBase64PublicKeyDecodesToNil() {
    let credential = PasskeyCredential(
      id: "test-credential",
      userID: UUID(),
      publicKeyBase64: "not-base64",
      signCount: 0
    )

    #expect(credential.publicKey == nil)
  }
}
