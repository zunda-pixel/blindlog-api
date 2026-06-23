import Foundation
import WebAuthn

enum Base64URLDecodingError: Error {
  case invalidCharacters
  case invalidLength
  case invalidData
}

extension String {
  func base64URLDecodedBytes() throws -> [UInt8] {
    guard !contains("+") && !contains("/") && !contains("=") else {
      throw Base64URLDecodingError.invalidCharacters
    }

    let remainder = count % 4
    guard remainder != 1 else {
      throw Base64URLDecodingError.invalidLength
    }

    var base64 = replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    if remainder > 0 {
      base64 += String(repeating: "=", count: 4 - remainder)
    }

    guard let data = Data(base64Encoded: base64) else {
      throw Base64URLDecodingError.invalidData
    }
    return Array(data)
  }
}

extension Collection where Element == UInt8 {
  func base64URLEncodedStringValue() -> String {
    Array(self).base64URLEncodedString().asString()
  }
}
