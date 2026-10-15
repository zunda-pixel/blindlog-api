import Configuration
import Foundation
import Testing

@testable import App

struct EventPassTests {
  private var values: [AbsoluteConfigKey: ConfigValue] {
    [
      "pass.certificate": "dGVzdA==",
      "pass.wwdr.certificate": "d3dkcg==",
      "pass.type.identifier": "pass.test.blindlog",
      "pass.team.identifier": "TESTTEAM",
      "pass.organization.name": "Blindlog",
      "pass.certificate.password": "test-password",
    ]
  }

  @Test(arguments: [
    "pass.certificate", "pass.wwdr.certificate", "pass.type.identifier",
    "pass.team.identifier", "pass.organization.name", "pass.certificate.password",
  ])
  func missingConfigurationFailsAtStartup(key: String) {
    var values = values
    values.removeValue(forKey: AbsoluteConfigKey(ConfigKey(key)))
    let config = ConfigReader(providers: [InMemoryProvider(values: values)])
    #expect(throws: (any Error).self) { try makePassConfiguration(config: config) }
  }

  @Test
  func configurationKeepsDecodedCertificateBytes() throws {
    let config = ConfigReader(providers: [InMemoryProvider(values: values)])
    let pass = try makePassConfiguration(config: config)
    #expect(pass.passCertificateData == Data("test".utf8))
    #expect(pass.wwdrCertificateData == Data("wwdr".utf8))
    #expect(pass.passCertificatePassword == "test-password")
  }

  @Test(arguments: ["pass.certificate", "pass.wwdr.certificate"])
  func invalidBase64FailsAtStartup(key: String) {
    var values = values
    values[AbsoluteConfigKey(ConfigKey(key))] = "!invalid!"
    let config = ConfigReader(providers: [InMemoryProvider(values: values)])
    #expect(throws: PassConfigurationError.self) { try makePassConfiguration(config: config) }
  }

  @Test
  func passEligibilityExcludesWaitlistedAndCanceledParticipants() {
    #expect(EventParticipantRecord.Status.registered.canIssuePass)
    #expect(EventParticipantRecord.Status.attended.canIssuePass)
    #expect(!EventParticipantRecord.Status.waitlisted.canIssuePass)
    #expect(!EventParticipantRecord.Status.canceled.canIssuePass)
  }

  @Test
  func malformedCertificateCannotProducePass() async throws {
    let config = ConfigReader(providers: [InMemoryProvider(values: values)])
    let configuration = try makePassConfiguration(config: config)
    await #expect(throws: (any Error).self) {
      try await makeEventPassData(configuration: configuration, content: testContent)
    }
  }

  private var testContent: EventPassContent {
    .init(
      eventID: UUID(), serialNumber: UUID().uuidString, title: "Test tasting",
      startsAt: Date(), endsAt: Date().addingTimeInterval(3600),
      venueName: "Test venue", venueAddress: "Tokyo", attendeeName: "Test attendee"
    )
  }
}

extension EventPassTests {
  /// Uses a throwaway self-signed identity, never an Apple production key.
  @Test
  func signedPassContainsExpectedTicketAndValidDetachedSignature() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("blindlog-pass-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try runTool(
      "openssl",
      [
        "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
        "-subj", "/CN=Blindlog Test Only", "-keyout", "key.pem", "-out", "cert.pem",
      ], in: directory)
    try runTool(
      "openssl",
      [
        "pkcs12", "-export", "-inkey", "key.pem", "-in", "cert.pem",
        "-out", "pass.p12", "-passout", "pass:test-password",
      ], in: directory)
    try runTool(
      "openssl",
      [
        "x509", "-in", "cert.pem", "-outform", "DER", "-out", "wwdr.cer",
      ], in: directory)
    var configuration = PassConfiguration(
      passCertificateData: try Data(contentsOf: directory.appendingPathComponent("pass.p12")),
      passCertificatePassword: "test-password",
      wwdrCertificateData: try Data(contentsOf: directory.appendingPathComponent("wwdr.cer")),
      passTypeIdentifier: "pass.test.blindlog", teamIdentifier: "TESTTEAM",
      organizationName: "Blindlog"
    )
    let content = testContent
    let passData = try await makeEventPassData(configuration: configuration, content: content)
    try passData.write(to: directory.appendingPathComponent("ticket.pkpass"))
    try runTool("unzip", ["-q", "ticket.pkpass", "-d", "unpacked"], in: directory)
    let unpacked = directory.appendingPathComponent("unpacked")
    let json = try #require(
      JSONSerialization.jsonObject(
        with: Data(contentsOf: unpacked.appendingPathComponent("pass.json")))
        as? [String: Any]
    )
    #expect(json["serialNumber"] as? String == content.serialNumber)
    #expect(json["passTypeIdentifier"] as? String == configuration.passTypeIdentifier)
    #expect(json["eventTicket"] != nil)
    let barcode = try #require((json["barcodes"] as? [[String: Any]])?.first)
    #expect(
      barcode["message"] as? String
        == "blindlog://events/\(content.eventID.uuidString)/tickets/\(content.serialNumber)")
    try runTool(
      "openssl",
      [
        "cms", "-verify", "-binary", "-inform", "DER", "-in", "unpacked/signature",
        "-content", "unpacked/manifest.json", "-noverify", "-out", "verified-manifest.json",
      ], in: directory)
    #expect(
      try Data(contentsOf: directory.appendingPathComponent("verified-manifest.json"))
        == Data(contentsOf: unpacked.appendingPathComponent("manifest.json"))
    )
    // A DER certificate has no private key, so signing must fail even though parsing succeeds.
    configuration.passCertificateData = configuration.wwdrCertificateData
    configuration.passCertificatePassword = nil
    let invalidSigningConfiguration = configuration
    await #expect(throws: (any Error).self) {
      try await makeEventPassData(configuration: invalidSigningConfiguration, content: content)
    }
  }

  private func runTool(_ tool: String, _ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    process.currentDirectoryURL = directory
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0, "\(tool) failed: \(process.terminationStatus)")
  }
}
