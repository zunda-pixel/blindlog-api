import Configuration
import Foundation
import Testing
@_spi(CMS) import X509
import ZipArchive

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
  /// Uses a committed test-only self-signed identity, never an Apple production key.
  @Test
  func signedPassContainsExpectedTicketAndValidDetachedSignature() async throws {
    // Public test fixtures only. These keys must never be used for real Wallet passes.
    let passCertificateData = try #require(Data(base64Encoded: Self.testPKCS12))
    let wwdrCertificateData = try #require(Data(base64Encoded: Self.testCertificateDER))
    var configuration = PassConfiguration(
      passCertificateData: passCertificateData,
      passCertificatePassword: "test-password",
      wwdrCertificateData: wwdrCertificateData,
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
    let expectedBarcode =
      "blindlog://events/\(content.eventID.uuidString)/tickets/\(content.serialNumber)"
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
      Issue.record("CMS detached signature verification failed: \(verification)")
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

  private static let testPKCS12 =
    "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"
  private static let testCertificateDER =
    "MIIDHTCCAgWgAwIBAgIUa9vwdmp9kzlA0cP6xR0NAMd7F78wDQYJKoZIhvcNAQELBQAwHTEbMBkGA1UEAwwSQmxpbmRsb2cgVGVzdCBPbmx5MCAXDTI2MTAxNTE1MDYwNVoYDzIxMjYwOTIxMTUwNjA1WjAdMRswGQYDVQQDDBJCbGluZGxvZyBUZXN0IE9ubHkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDYnVkHwGPFalj26MmSf6InXpYcNJEjACdfrnV24FyUGiwTl9T+/382MH4amAmedvICWoU2ZGci38oUXSS6sNpvf+6d1BjoCG+UHI6BThZkB8abg/F5Mt3aFBOzFf5MKBpEqSRqTy00AwnWazHYmJRm5qfaGf2C+bZ0+0SjGBjLOH+1CmeDgCNfjUOZxw/NVxIWKoToiU2hf2jFwbbyXUDcZapXFe5neyHcZWoLTV19k3N4DM81OM78r5z/O/zCTZ4ru8Nopt2LrLSI2panjsx5cUbIuz+0/krysKP5f6Ri+0OuX1GF0GG2xzHlYtCjSZln8K4zi5VbmrjGS7ogBfE5AgMBAAGjUzBRMB0GA1UdDgQWBBSyheR3rM0mUCsHF6OquQqAdnuV4zAfBgNVHSMEGDAWgBSyheR3rM0mUCsHF6OquQqAdnuV4zAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBL0D71Jkhx8kaMrdxiRkm4T9rkmC8Iru6/Ye9Du9x3G1K6r6S7Yo6ZV9eHoeHyWyjocc+ZL2vz2d8LhvLHjwB/IFbyBe0MDcqCCZXiJdjppZykhsEsJOnuXoDaDn7zUgL2aEanu6qbExMo3NWHd306l2P0KDaW/E5H9v2jQAXpkzK7VedBboB2mdggL698Zwa8x/m+d0gNOP38MX0cKGnFSaf1008ZpE7JEU8nUwic3NgXQn1cot4qQRCr8h/io6UoXIBZY1k3A7NozMpYuj7VLdUIse+GXmu43u6SxVF8hir2F9MbbwTgjhK8BxHNrIg3/2vQeiIplZ+M52w7kjrm"
}
