import Foundation

enum APIErrorCode: String, Sendable {
  case badRequest = "bad_request"
  case unauthorized
  case notFound = "not_found"

  case invalidRequest = "invalid_request"
  case challengeVerifyFailed = "challenge_verify_failed"
  case credentialAlreadyExists = "credential_already_exists"
  case persistFailed = "persist_failed"
  case registrationDecodeFailed = "registration_decode_failed"
  case registrationValidateFailed = "registration_validate_failed"
}

private enum APIErrorResponseFactory {
  static func make(_ code: APIErrorCode, message: String? = nil) -> Components.Schemas.APIError {
    Components.Schemas.APIError(error: code.rawValue, message: message)
  }
}

extension Operations.AddPasskey.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.ConfirmEmail.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateChallenge.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateEvent.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateEventQuestion.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateEventQuestionCorrectAnswer.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateEventQuestionResponse.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateImage.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateImageUploadURL.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateTokenFromEmail.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateTokenFromPasskey.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateUser.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.CreateUserProfile.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetEvent.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetEvents.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetMe.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetUserOrganizedEvents.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetUserParticipatingEvents.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetUserProfile.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetUsers.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetWineRegionTypes.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetWineRegions.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetWineStyles.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.GetWineVarieties.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.RefreshToken.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.RegisterEventParticipant.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.RevokeToken.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.SendConfirmEmail.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.SendEmailForToken.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.UpdateEvent.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.UpdateEventQuestion.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.UpdateEventQuestionCorrectAnswer.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}

extension Operations.UpdateMyEventQuestionResponse.Output {
  static var badRequest: Self { badRequest(.badRequest) }
  static func badRequest(_ code: APIErrorCode, message: String? = nil) -> Self {
    .badRequest(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var notFound: Self { notFound(.notFound) }
  static func notFound(_ code: APIErrorCode, message: String? = nil) -> Self {
    .notFound(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
  static var unauthorized: Self { unauthorized(.unauthorized) }
  static func unauthorized(_ code: APIErrorCode, message: String? = nil) -> Self {
    .unauthorized(.init(body: .json(APIErrorResponseFactory.make(code, message: message))))
  }
}
