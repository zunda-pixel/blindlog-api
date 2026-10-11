import ExtrasBase64
import Foundation

extension String {
  func base64URLDecodedBytes() throws -> [UInt8] {
    return try base64decoded(options: [.base64UrlAlphabet, .omitPaddingCharacter])
  }
}

extension Collection where Element == UInt8 {
  func base64URLEncodedStringValue() -> String {
    String(base64Encoding: self, options: [.base64UrlAlphabet, .omitPaddingCharacter])
  }
}
