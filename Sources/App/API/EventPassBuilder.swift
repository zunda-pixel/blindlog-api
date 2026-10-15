import Foundation
import PassBuilder
import UUIDV7

/// Configuration required to build and sign Apple Wallet passes for events.
///
/// Certificate bytes stay in memory and are never written to temporary files.
struct PassConfiguration: Sendable {
  /// Pass Type ID signing certificate (PKCS#12 / `.p12`).
  var passCertificateData: Data
  /// Password protecting the `.p12` bundle, if any.
  var passCertificatePassword: String?
  /// Apple WWDR intermediate certificate (DER / `.cer`).
  var wwdrCertificateData: Data
  /// The pass type identifier registered with Apple, e.g. `pass.com.example.event`.
  var passTypeIdentifier: String
  /// The Apple Developer Team identifier.
  var teamIdentifier: String
  /// The organization name displayed on the pass.
  var organizationName: String
}

enum PassConfigurationError: Error, CustomStringConvertible {
  case invalidCertificate

  var description: String {
    switch self {
    case .invalidCertificate:
      "Pass certificate configuration must be valid Base64"
    }
  }
}

/// Input describing the event ticket to render on the pass.
struct EventPassContent {
  var eventID: UUID
  var serialNumber: String
  var title: String
  var startsAt: Date
  var endsAt: Date
  var venueName: String
  var venueAddress: String
  var attendeeName: String?
}

/// Builds and signs an Apple Wallet event ticket, returning the `.pkpass` bytes.
func makeEventPassData(
  configuration: PassConfiguration,
  signer: PassSigner,
  content: EventPassContent
) async throws -> Data {
  var package = PassPackage()
  package.pass.passTypeIdentifier = configuration.passTypeIdentifier
  package.pass.teamIdentifier = configuration.teamIdentifier
  package.pass.organizationName = configuration.organizationName
  package.pass.serialNumber = content.serialNumber
  package.pass.description = content.title
  package.pass.logoText = content.title
  package.pass.relevantDate = content.startsAt

  var fields = Pass.Fields()
  fields.primaryFields = [
    Pass.FieldContent(key: "event", label: "EVENT", value: .text(content.title))
  ]

  var dateField = Pass.FieldContent(key: "starts", label: "DATE", value: .date(content.startsAt))
  dateField.dateStyle = .medium
  dateField.timeStyle = .short
  var secondaryFields = [dateField]
  if let attendeeName = content.attendeeName, !attendeeName.isEmpty {
    secondaryFields.append(
      Pass.FieldContent(key: "attendee", label: "ATTENDEE", value: .text(attendeeName))
    )
  }
  fields.secondaryFields = secondaryFields

  fields.auxiliaryFields = [
    Pass.FieldContent(key: "venue", label: "VENUE", value: .text(content.venueName))
  ]

  var endsField = Pass.FieldContent(key: "ends", label: "ENDS", value: .date(content.endsAt))
  endsField.dateStyle = .medium
  endsField.timeStyle = .short
  fields.backFields = [
    Pass.FieldContent(key: "address", label: "ADDRESS", value: .text(content.venueAddress)),
    endsField,
  ]

  package.pass.eventTicket = fields

  var barcode = Pass.Barcode()
  barcode.format = .qr
  barcode.message =
    "blindlog://events/\(content.eventID.uuidString)/tickets/\(content.serialNumber)"
  barcode.messageEncoding = "iso-8859-1"
  barcode.altText = content.serialNumber
  package.pass.barcodes = [barcode]

  var icon = PassImage()
  icon.times1 = try passIconFile(named: "icon")
  icon.times2 = try passIconFile(named: "icon@2x")
  icon.times3 = try passIconFile(named: "icon@3x")
  package.icon = icon

  // `signPass` writes to disk, so use a unique temporary directory and read the
  // resulting `.pkpass` back into memory.
  let workingDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("blindlog-pass-\(UUID.uuidV7String())", isDirectory: true)
  try FileManager.default.createDirectory(
    at: workingDirectory,
    withIntermediateDirectories: true
  )
  defer { try? FileManager.default.removeItem(at: workingDirectory) }

  let destination = workingDirectory.appendingPathComponent("\(content.serialNumber).pkpass")
  let signedURL = try await signer.signPass(
    package,
    destination: destination,
    options: [.zipOutput, .overwriteExisting]
  )
  return try Data(contentsOf: signedURL)
}

private func passIconFile(named name: String) throws -> PassImageFile {
  guard
    let url = Bundle.module.url(
      forResource: name, withExtension: "png", subdirectory: "PassIcon"
    )
  else {
    throw CocoaError(.fileNoSuchFile)
  }
  return try PassImageFile(data: Data(contentsOf: url), fileType: .png)
}
