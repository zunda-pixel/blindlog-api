import Algorithms
import Crypto
import Foundation
import Logging

// swift-log metadata helpers shared by OTel logs and Cloud Run stdout logs.
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

enum AppStructuredLog {
  static func emit(
    level: Logger.Level,
    eventName: String,
    message: Logger.Message,
    metadata: Logger.Metadata
  ) {
    guard
      let data = makeLineData(
        level: level,
        eventName: eventName,
        message: message,
        metadata: metadata
      )
    else {
      return
    }

    FileHandle.standardOutput.write(data)
  }

  static func makeRecord(
    level: Logger.Level,
    eventName: String,
    message: Logger.Message,
    metadata: Logger.Metadata
  ) -> [String: Any] {
    var record: [String: Any] = [
      "severity": cloudLoggingSeverity(for: level),
      "message": message.description,
      "eventName": eventName,
      "metadata": jsonObject(from: metadata),
    ]

    if let errorType = stringValue(metadata["error.type"]) {
      record["error"] = ["type": errorType]
    }

    return record
  }

  private static func makeLineData(
    level: Logger.Level,
    eventName: String,
    message: Logger.Message,
    metadata: Logger.Metadata
  ) -> Data? {
    let record = makeRecord(
      level: level,
      eventName: eventName,
      message: message,
      metadata: metadata
    )

    guard JSONSerialization.isValidJSONObject(record),
      let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    else {
      return nil
    }

    var line = data
    line.append(0x0a)
    return line
  }

  private static func jsonObject(from metadata: Logger.Metadata) -> [String: Any] {
    metadata.reduce(into: [:]) { result, element in
      result[element.key] = jsonValue(from: element.value)
    }
  }

  private static func jsonValue(from value: Logger.Metadata.Value) -> Any {
    switch value {
    case .string(let string):
      return string
    case .stringConvertible(let value):
      return value.description
    case .array(let values):
      return values.map(jsonValue(from:))
    case .dictionary(let metadata):
      return jsonObject(from: metadata)
    }
  }

  private static func stringValue(_ value: Logger.Metadata.Value?) -> String? {
    guard case .string(let string) = value else {
      return nil
    }
    return string
  }

  private static func cloudLoggingSeverity(for level: Logger.Level) -> String {
    switch level {
    case .trace:
      return "DEBUG"
    case .debug:
      return "DEBUG"
    case .info:
      return "INFO"
    case .notice:
      return "NOTICE"
    case .warning:
      return "WARNING"
    case .error:
      return "ERROR"
    case .critical:
      return "CRITICAL"
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
    let metadata = AppLogMetadata.make(
      eventName: eventName,
      metadata: metadata,
      error: error
    )

    AppStructuredLog.emit(
      level: level,
      eventName: eventName,
      message: message,
      metadata: metadata
    )

    self.log(
      level: level,
      message,
      metadata: metadata
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
