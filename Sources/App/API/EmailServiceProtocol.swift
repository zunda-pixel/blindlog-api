import EmailService

protocol EmailServiceProtocol: Sendable {
  func send(_ email: EmailMessage) async throws -> EmailResponse.Result
}

extension EmailService.Client: EmailServiceProtocol {}
