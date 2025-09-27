import Hummingbird

extension BasicRequestContext {
  @TaskLocal static var current: BasicRequestContext?
}

/// Middleware that adds the RequestContext as a TaskLocal so it is accessible from OpenAPI handlers.
///
/// This middleware should be the last in the middleware chain to ensure all edits to the RequestContext
/// are passed to the Task Local
struct OpenAPIRequestContextMiddleware: RouterMiddleware {
  typealias Context = BasicRequestContext

  func handle(
    _ request: Request,
    context: Context,
    next: (Request, Context) async throws -> Response
  ) async throws -> Response {
    try await BasicRequestContext.$current.withValue(context) {
      try await next(request, context)
    }
  }
}
