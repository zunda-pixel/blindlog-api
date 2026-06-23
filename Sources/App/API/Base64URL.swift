import ExtrasBase64
import Foundation

enum Base64URLDecodingError: Error {
  case paddedValue
}

extension String {
  func base64URLDecodedBytes() throws -> [UInt8] {
    // Keep the challenge representation URL-safe itself, instead of relying on
    // callers to percent-encode standard Base64 when it crosses URL boundaries.
    guard !contains("=") else {
      throw Base64URLDecodingError.paddedValue
    }
    return try base64decoded(options: [.base64UrlAlphabet, .omitPaddingCharacter])
  }
}

extension Collection where Element == UInt8 {
  func base64URLEncodedStringValue() -> String {
    String(base64Encoding: self, options: [.base64UrlAlphabet, .omitPaddingCharacter])
  }
}
