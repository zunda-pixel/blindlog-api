import Foundation
import Hummingbird
import PostgresNIO
import SQLKit
import WebAuthn

extension API {
  func addPasskey(
    _ input: Operations.addPasskey.Input
  ) async throws -> Operations.addPasskey.Output {
    guard let userID = BearerAuthenticateUser.current?.userID else {
      throw HTTPError(.unauthorized)
    }
    // 1. Parse request payload
    guard case .json(let body) = input.body else { throw HTTPError(.badRequest) }
    let bodyData = try JSONEncoder().encode(body)
    let registrationCredential = try JSONDecoder().decode(
      RegistrationCredential.self,
      from: bodyData
    )

    // 2. Verify and delete challenge atomically
    let challengeData = Data(input.query.challenge.data)

    let row = try await database.write { db in
      try await Challenge
        .delete()
        .where {
          $0.challenge.eq(challengeData)
            .and(
              $0.userID.is(nil)
                .and(
                  $0.purpose.eq(Challenge.Purpose.authentication)
                    .and($0.expiredDate.gt(Date.currentTimestamp))))
        }
        .returning(\.self)
        .fetchOne(db)
    }

    guard row != nil else {
      throw HTTPError(.badRequest)
    }

    // 3. Validate WebAuthn registration data
    let credential = try await webAuthn.finishRegistration(
      challenge: Array(input.query.challenge.data),
      credentialCreationData: registrationCredential,
      confirmCredentialIDNotRegisteredYet: { credentialID in
        let credential = try await database.read { db in
          try await PasskeyCredential
            .where { $0.id.eq(credentialID) }
            .select { _ in 1 }
            .fetchOne(db)
        }

        return credential == nil
      }
    )

    // 4. Persist credential metadata
    try await database.write { db in
      try await PasskeyCredential.insert {
        PasskeyCredential(
          id: registrationCredential.id.asString(),
          userID: userID,
          publicKey: Data(credential.publicKey),
          signCount: Int64(credential.signCount)
        )
      }
      .execute(db)
    }

    return .ok
  }
}
