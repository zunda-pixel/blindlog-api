import Foundation
import Hummingbird
import HummingbirdAuth
import JWTKit
import PostgresNIO

struct BearerTokenMiddleware<Context: RequestContext>: RouterMiddleware {
  var jwtKeyCollection: JWTKeyCollection

  func userID(
    _ request: Request,
    context: Context
  ) async throws -> UUID? {
    guard let jwtToken = request.headers.bearer?.token else { return nil }

    // get payload and verify its contents
    let payload: JWTPayloadData
    do {
      payload = try await self.jwtKeyCollection.verify(jwtToken, as: JWTPayloadData.self)
    } catch {
      context.logger.debug("couldn't verify token")
      return nil
    }
    // get user id and name from payload
    guard let userID = UUID(uuidString: payload.subject.value) else {
      context.logger.debug("Invalid JWT subject \(payload.subject.value)")
      return nil
    }
    // verify expiration is not over.
    guard payload.expiration.value > Date() else {
      context.logger.debug("Token expired")
      return nil
    }

    return userID
  }

  func handle(
    _ request: Request,
    context: Context,
    next: (Request, Context) async throws -> Response
  ) async throws -> Response {
    let userID = try await userID(request, context: context)
    guard let userID else {
      return try await next(request, context)
    }

    return try await User.$currentUserID.withValue(userID) {
      try await next(request, context)
    }
  }
}

extension User {
  @TaskLocal static var currentUserID: UUID?
}
