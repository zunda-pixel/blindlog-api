import Configuration
import Foundation
import Subprocess
import Testing
import ZipArchive
@_spi(CMS) import X509

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
  func passEligibilityExcludesWaitlistedAndCanceledParticipants() {
    #expect(EventParticipantRecord.Status.registered.canIssuePass)
    #expect(EventParticipantRecord.Status.attended.canIssuePass)
    #expect(!EventParticipantRecord.Status.waitlisted.canIssuePass)
    #expect(!EventParticipantRecord.Status.canceled.canIssuePass)
  }

  @Test
  func malformedCertificateCannotProducePass() throws {
    let config = ConfigReader(providers: [InMemoryProvider(values: values)])
    let configuration = try makePassConfiguration(config: config)
    #expect(throws: (any Error).self) {
      try makePassSigner(configuration: configuration)
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
    try await runTool(
      "openssl",
      [
        "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
        "-subj", "/CN=Blindlog Test Only", "-keyout", "key.pem", "-out", "cert.pem",
      ], in: directory)
    try await runTool(
      "openssl",
      [
        "pkcs12", "-export", "-inkey", "key.pem", "-in", "cert.pem",
        "-out", "pass.p12", "-passout", "pass:test-password",
      ], in: directory)
    try await runTool(
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
    let signer = try makePassSigner(configuration: configuration)
    let passData = try await makeEventPassData(
      configuration: configuration, signer: signer, content: content
    )
    let archive = try ZipArchiveReader<ZipMemoryStorage<[UInt8]>>(buffer: Array(passData))
    let entries = try archive.readDirectory()

    func fileData(_ filename: String) throws -> Data {
      let entry = try #require(entries.first { $0.filename.string == filename })
      return Data(try archive.readFile(entry))
    }

    struct PassJSON: Decodable {
      struct Barcode: Decodable {
        let message: String
      }
      let serialNumber: String
      let passTypeIdentifier: String
      let eventTicket: EventTicket

      struct EventTicket: Decodable {}
      let barcodes: [Barcode]
    }

    let passJSON = try JSONDecoder().decode(PassJSON.self, from: fileData("pass.json"))
    let expectedSerialNumber = content.serialNumber
    let actualSerialNumber = passJSON.serialNumber
    #expect(actualSerialNumber == expectedSerialNumber)
    let expectedPassTypeIdentifier = configuration.passTypeIdentifier
    let actualPassTypeIdentifier = passJSON.passTypeIdentifier
    #expect(actualPassTypeIdentifier == expectedPassTypeIdentifier)
    let barcode = try #require(passJSON.barcodes.first)
    let expectedBarcode = "blindlog://events/\\(content.eventID.uuidString)/tickets/\\(content.serialNumber)"
    let actualBarcode = barcode.message
    #expect(actualBarcode == expectedBarcode)

    let manifest = try fileData("manifest.json")
    let signature = try fileData("signature")
    let testCertificate = try Certificate(
      derEncoded: Array(configuration.wwdrCertificateData)
    )
    let verification = await CMS.isValidSignature(
      dataBytes: manifest,
      signatureBytes: signature,
      trustRoots: CertificateStore([testCertificate])
    ) {
      RFC5280Policy()
    }
    guard case .success = verification else {
      Issue.record("CMS detached signature verification failed: \\(verification)")
      return
    }
    // A DER certificate has no private key, so signing must fail even though parsing succeeds.
    configuration.passCertificateData = configuration.wwdrCertificateData
    configuration.passCertificatePassword = nil
    let invalidSigningConfiguration = configuration
    do {
      let invalidSigner = try makePassSigner(configuration: invalidSigningConfiguration)
      await #expect(throws: (any Error).self) {
        try await makeEventPassData(
          configuration: invalidSigningConfiguration, signer: invalidSigner, content: content)
      }
    } catch {
      // Invalid signing material may be rejected during signer initialization.
    }
  }

  private func runTool(_ tool: String, _ arguments: [String], in directory: URL) async throws {
    let result = try await Subprocess.run(
      .name(tool),
      arguments: Arguments(arguments),
      workingDirectory: .init(stringLiteral: directory.path),
      output: .discarded
    )
    #expect(result.terminationStatus.isSuccess, "\(tool) failed: \(result.terminationStatus)")
  }
}
