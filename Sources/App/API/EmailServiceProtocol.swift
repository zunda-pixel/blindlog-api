import EmailService

protocol EmailServiceProtocol: Sendable {
  func sendEmail(_ email: EmailMessage) async throws
}

extension EmailService.Client: EmailServiceProtocol {
  func sendEmail(_ email: EmailMessage) async throws {
    _ = try await send(email)
  }
}
