import Logging

extension Logger {
  /// Builds OTel `exception.*` semantic-convention metadata for an error,
  /// optionally merged with caller-provided fields (caller wins on conflicts).
  static func errorMetadata(
    _ error: any Error,
    _ extra: Logger.Metadata = [:]
  ) -> Logger.Metadata {
    var metadata = extra
    metadata["exception.type"] = .string(String(reflecting: type(of: error)))
    metadata["exception.message"] = .string(String(describing: error))
    return metadata
  }
}
