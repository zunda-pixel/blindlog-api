import HTTPTypes
import Hummingbird
import Logging

struct ErrorLoggingMiddleware<Context: RequestContext>: RouterMiddleware {
  func handle(
    _ request: Request,
    context: Context,
    next: @concurrent (Request, Context) async throws -> Response
  ) async throws -> Response {
    do {
      return try await next(request, context)
    } catch {
      let status = (error as? any HTTPResponseError)?.status ?? .internalServerError
      let level: Logger.Level = status.kind == .serverError ? .error : .warning

      context.logger.appLog(
        level: level,
        eventName: "http.server.request.error",
        "Request failed",
        metadata: [
          "http.request.method": .string(request.method.rawValue),
          "http.response.status_code": .stringConvertible(status.code),
          "http.route": .string(context.endpointPath ?? "unknown"),
          "url.path": .string(request.uri.path),
        ],
        error: error
      )

      throw error
    }
  }
}
