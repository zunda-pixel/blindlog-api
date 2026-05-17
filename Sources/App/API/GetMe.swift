import Foundation
import Hummingbird
import Logging

extension API {
  func getMe(_ input: Operations.GetMe.Input) async throws -> Operations.GetMe.Output {
    guard let userID = UserTokenContext.currentUserID else {
      return .unauthorized
    }

    let profile: Components.Schemas.UserProfile?
    do {
      profile = try await getProfile(userID: userID)
    } catch {
      AppRequestContext.current?.logger.appError(
        eventName: "user.profile_read_failed",
        "Failed to fetch user profile",
        metadata: AppLogMetadata.userID(userID).merging([
          "db.operation": .string("select")
        ]) { _, new in new },
        error: error
      )
      return .badRequest
    }

    guard let profile else { return .notFound }

    return .ok(.init(body: .json(profile)))
  }
}
