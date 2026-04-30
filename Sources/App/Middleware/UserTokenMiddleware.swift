import Foundation
import Hummingbird
import HummingbirdAuth
import JWTKit
import PostgresNIO

struct UserTokenMiddleware<Context: RequestContext>: RouterMiddleware {
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
      context.logger.appLog(
        level: .debug,
        eventName: "auth.user_token.verify_failed",
        "Couldn't verify token",
        error: error
      )
      return nil
    }
    // get user id and name from payload
    guard let userID = UUID(uuidString: payload.subject.value) else {
      context.logger.appLog(
        level: .debug,
        eventName: "auth.user_token.invalid_subject",
        "Invalid JWT subject"
      )
      return nil
    }
    // verify expiration is not over
    guard payload.expiration.value > Date() else {
      context.logger.appLog(
        level: .debug,
        eventName: "auth.user_token.expired",
        "Token expired",
        metadata: AppLogMetadata.userID(userID)
      )
      return nil
    }
    // verify token type
    guard payload.tokenType == .token else {
      context.logger.appLog(
        level: .debug,
        eventName: "auth.user_token.invalid_type",
        "Token type is not token",
        metadata: AppLogMetadata.userID(userID)
      )
      return nil
    }

    return userID
  }

  func handle(
    _ request: Request,
    context: Context,
    next: @concurrent (Request, Context) async throws -> Response
  ) async throws -> Response {
    let userID = try await userID(request, context: context)
    guard let userID else {
      return try await next(request, context)
    }

    return try await UserTokenContext.$currentUserID.withValue(userID) {
      try await next(request, context)
    }
  }
}

enum UserTokenContext {
  @TaskLocal static var currentUserID: UUID?
}
