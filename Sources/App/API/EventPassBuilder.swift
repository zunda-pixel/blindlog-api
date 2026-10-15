import Foundation
import PassBuilder

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
  let package = try PassPackage(configuration: configuration, content: content)
  return try await signer.signPassData(package)
}

extension PassPackage {
  init(configuration: PassConfiguration, content: EventPassContent) throws {
    self.init()
    pass.passTypeIdentifier = configuration.passTypeIdentifier
    pass.teamIdentifier = configuration.teamIdentifier
    pass.organizationName = configuration.organizationName
    pass.serialNumber = content.serialNumber
    pass.description = content.title
    pass.logoText = content.title
    pass.relevantDate = content.startsAt

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

    pass.eventTicket = fields

    var barcode = Pass.Barcode()
    barcode.format = .qr
    barcode.message =
      "blindlog://events/\(content.eventID.uuidString)/tickets/\(content.serialNumber)"
    barcode.messageEncoding = "iso-8859-1"
    barcode.altText = content.serialNumber
    pass.barcodes = [barcode]

    var icon = PassImage()
    icon.times1 = try passIconFile(named: "icon")
    icon.times2 = try passIconFile(named: "icon@2x")
    icon.times3 = try passIconFile(named: "icon@3x")
    self.icon = icon

  }
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
