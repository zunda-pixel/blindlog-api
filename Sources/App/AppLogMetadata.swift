import Algorithms
import Crypto
import Foundation
import Logging

enum AppLogMetadata {
  static func make(
    eventName: String,
    metadata: Logger.Metadata = [:],
    error: (any Error)? = nil
  ) -> Logger.Metadata {
    var metadata = sanitized(metadata)
    metadata["event.name"] = .string(eventName)

    // Only the error type is recorded automatically. The stringified description
    // (`String(describing: error)`) often contains user-supplied data — emails in
    // validation errors, token snippets in JWT errors — and would bypass the
    // key-based sanitization here. Call sites that need extra context should
    // pass safe, structured fields via the `metadata` parameter.
    if let error {
      metadata["error.type"] = .string(String(reflecting: Swift.type(of: error)))
    }

    return metadata
  }

  static func sanitized(_ metadata: Logger.Metadata) -> Logger.Metadata {
    metadata.filter { key, _ in
      !isSensitiveMetadataKey(key)
    }
  }

  static func userID(_ userID: UUID?) -> Logger.Metadata {
    guard let userID else { return [:] }
    return ["user.id": .string(userID.uuidString)]
  }

  static func emailSHA256(_ email: String) -> Logger.Metadata {
    ["email.sha256": .string(sha256Hex(normalizedEmail(email)))]
  }

  private static func normalizedEmail(_ email: String) -> String {
    email.trimming(while: \.isWhitespace).lowercased()
  }

  private static func sha256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    let hexDigits = Array("0123456789abcdef".utf8)
    let bytes = digest.flatMap { byte in
      [
        hexDigits[Int(byte >> 4)],
        hexDigits[Int(byte & 0x0f)],
      ]
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static let sensitiveKeySegments: Set<String> = [
    "body",
    "challenge",
    "credential",
    "email",
    "otp",
    "password",
    "rawid",
    "token",
  ]

  private static func isSensitiveMetadataKey(_ key: String) -> Bool {
    let key = key.lowercased()
    if key == "email.sha256" {
      return false
    }
    return key.split(separator: ".").contains { segment in
      sensitiveKeySegments.contains(String(segment))
    }
  }
}

extension Logger {
  func appLog(
    level: Logger.Level,
    eventName: String,
    _ message: Logger.Message,
    metadata: Logger.Metadata = [:],
    error: (any Error)? = nil
  ) {
    self.log(
      level: level,
      message,
      metadata: AppLogMetadata.make(
        eventName: eventName,
        metadata: metadata,
        error: error
      )
    )
  }

  func appError(
    eventName: String,
    _ message: Logger.Message,
    metadata: Logger.Metadata = [:],
    error: any Error
  ) {
    appLog(
      level: .error,
      eventName: eventName,
      message,
      metadata: metadata,
      error: error
    )
  }
}
