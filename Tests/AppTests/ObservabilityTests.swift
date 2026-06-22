import Configuration
import Foundation
import Logging
import OTel
import Testing

@testable import App

struct ObservabilityTests {
  @Test
  func otelConfigurationCanBeBuiltRepeatedlyWithoutBootstrappingGlobals() {
    var arguments = TestArguments()
    arguments.env = .production
    arguments.logLevel = .debug

    let config = ConfigReader(
      providers: [
        InMemoryProvider(values: [
          "cloud.run.region": "asia-northeast1",
          "k.configuration": "blindlog-api",
          "k.revision": "blindlog-api-00001",
          "k.service": "blindlog-api",
        ])
      ]
    )

    let first = makeOTelConfiguration(arguments: arguments, config: config)
    let second = makeOTelConfiguration(arguments: arguments, config: config)

    #expect(first.serviceName == "blindlog-api")
    #expect(second.serviceName == "blindlog-api")
    #expect(first.logs.otlpExporter.endpoint == "http://localhost:4318")
    #expect(first.logs.otlpExporter.protocol == .httpProtobuf)
    #expect(first.metrics.otlpExporter.protocol == .httpProtobuf)
    #expect(first.traces.otlpExporter.protocol == .httpProtobuf)
    #expect(first.resourceAttributes["deployment.environment.name"] == "production")
    #expect(first.resourceAttributes["service.version"] == "blindlog-api-00001")
    #expect(first.resourceAttributes["gcp.cloud_run.revision"] == "blindlog-api-00001")
    #expect(first.resourceAttributes["cloud.region"] == "asia-northeast1")
  }

  @Test
  func appLogMetadataRemovesSensitiveFieldsAndKeepsSafeFields() {
    let metadata = AppLogMetadata.make(
      eventName: "test.event",
      metadata: [
        "body": "request-body",
        "challenge": "challenge-value",
        "credential": "credential-value",
        "db.operation": "select",
        "email": "user@example.com",
        "email.sha256": "safe-hash",
        "http.request.body": "raw-body",
        "password": "password-value",
        "token": "token-value",
        "user.email": "user@example.com",
        "user.id": "user-123",
      ],
      error: TestLogError.example
    )

    #expect(metadata["body"] == nil)
    #expect(metadata["challenge"] == nil)
    #expect(metadata["credential"] == nil)
    #expect(metadata["email"] == nil)
    #expect(metadata["http.request.body"] == nil)
    #expect(metadata["password"] == nil)
    #expect(metadata["token"] == nil)
    #expect(metadata["user.email"] == nil)

    #expect(stringValue(metadata["event.name"]) == "test.event")
    #expect(stringValue(metadata["db.operation"]) == "select")
    #expect(stringValue(metadata["email.sha256"]) == "safe-hash")
    #expect(stringValue(metadata["user.id"]) == "user-123")
    // error.message is intentionally not emitted to avoid leaking the
    // stringified error description (which can contain user data).
    #expect(metadata["error.message"] == nil)
    #expect(stringValue(metadata["error.type"])?.contains("TestLogError") == true)
  }

  @Test
  func structuredLogRecordKeepsCloudLoggingFieldsAndSanitizesMetadata() throws {
    let metadata = AppLogMetadata.make(
      eventName: "auth.passkey.registration_validate_failed",
      metadata: [
        "credential": "raw-credential",
        "db.operation": "select",
        "user.id": "user-123",
      ],
      error: TestLogError.example
    )

    let record = AppStructuredLog.makeRecord(
      level: .error,
      eventName: "auth.passkey.registration_validate_failed",
      message: "Failed to validate WebAuthn registration",
      metadata: metadata
    )

    #expect(record["severity"] as? String == "ERROR")
    #expect(record["eventName"] as? String == "auth.passkey.registration_validate_failed")
    #expect(record["message"] as? String == "Failed to validate WebAuthn registration")

    let recordMetadata = try #require(record["metadata"] as? [String: Any])
    #expect(recordMetadata["credential"] == nil)
    #expect(recordMetadata["db.operation"] as? String == "select")
    #expect(recordMetadata["user.id"] as? String == "user-123")
    #expect(recordMetadata["event.name"] as? String == "auth.passkey.registration_validate_failed")

    let error = try #require(record["error"] as? [String: String])
    #expect(error["type"]?.contains("TestLogError") == true)
    #expect(JSONSerialization.isValidJSONObject(record))
  }

  @Test
  func appLogMetadataKeepsKeysThatOnlyContainSensitiveFragmentsAsSubstrings() {
    // Keys whose dotted segments don't exactly match a sensitive name should
    // pass through, even if they contain a sensitive word as a substring.
    let metadata = AppLogMetadata.make(
      eventName: "test.event",
      metadata: [
        "antibody.id": "abc",
        "rawidempotency.key": "xyz",
      ]
    )

    #expect(stringValue(metadata["antibody.id"]) == "abc")
    #expect(stringValue(metadata["rawidempotency.key"]) == "xyz")
  }

  @Test
  func emailHashMetadataDoesNotExposeRawEmail() {
    let metadata = AppLogMetadata.emailSHA256(" User@Example.COM ")
    let hash = stringValue(metadata["email.sha256"])

    #expect(hash != nil)
    #expect(hash?.count == 64)
    #expect(hash != "User@Example.COM")
  }

  private func stringValue(_ value: Logger.Metadata.Value?) -> String? {
    guard case .string(let string) = value else {
      return nil
    }
    return string
  }
}

private enum TestLogError: Error, CustomStringConvertible {
  case example

  var description: String {
    "example"
  }
}
