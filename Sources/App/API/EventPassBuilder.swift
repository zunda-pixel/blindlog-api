import Foundation
import PassBuilder
import UUIDV7

/// Configuration required to build and sign Apple Wallet passes for events.
///
/// The certificates are decoded from configuration at startup and written to
/// temporary files, because `PassCertificate` loads certificates from file URLs.
struct PassConfiguration: Sendable {
  /// File URL of the Pass Type ID signing certificate (PKCS#12 / `.p12`).
  var passCertificateURL: URL
  /// Password protecting the `.p12` bundle, if any.
  var passCertificatePassword: String?
  /// File URL of the Apple WWDR intermediate certificate (DER / `.cer`).
  var wwdrCertificateURL: URL
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

  // Apple Wallet requires an icon. Bundle a small default icon and reuse it for
  // every scale variant.
  if let iconData = Data(base64Encoded: defaultPassIconPNGBase64) {
    let iconFile = PassImageFile(data: iconData, fileType: .png)
    var icon = PassImage()
    icon.times1 = iconFile
    icon.times2 = iconFile
    icon.times3 = iconFile
    package.icon = icon
    package.logo = icon
  }

  let passCertificate = try PassCertificate(
    url: configuration.passCertificateURL,
    password: configuration.passCertificatePassword
  )
  let wwdrCertificate = try PassCertificate(url: configuration.wwdrCertificateURL)
  let signer = PassSigner(
    passCertificate: passCertificate,
    wwdrCertificate: wwdrCertificate
  )

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

/// A 38×38 solid-color PNG used as the default pass icon.
private let defaultPassIconPNGBase64 =
  "iVBORw0KGgoAAAANSUhEUgAAACYAAAAmCAYAAACoPemuAAAANklEQVR42u3OMQkAAAgAMBt52sv+oDUEd+xfdNZcFGJiYmJiYmJiYmJiYmJiYmJiYmJiYv9iC7XCYVOA07SRAAAAAElFTkSuQmCC"
