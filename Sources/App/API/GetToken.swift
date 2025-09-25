import Foundation
import Hummingbird
import PostgresNIO
import SQLKit
import StructuredQueriesPostgres
import WebAuthn

extension API {
  func createToken(
    _ input: Operations.createToken.Input
  ) async throws -> Operations.createToken.Output {
    // 1. Parse request payload
    guard case .json(let bodyData) = input.body else {
      throw HTTPError(.badRequest)
    }

    let data = try JSONEncoder().encode(bodyData)

    let credential = try JSONDecoder().decode(
      AuthenticationCredential.self,
      from: data
    )

    // 2. Verify and delete challenge atomically
    let challengeData = try Data(bodyData.challenge.base64decoded())

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

    // 3. Load stored credential
    let passkeyCredential = try await database.read { db in
      try await PasskeyCredential
        .select(\.self)
        .where { $0.id.eq(credential.id.asString()) }
        .limit(1)
        .fetchOne(db)
    }

    guard let passkeyCredential else {
      throw HTTPError(.internalServerError)
    }

    // 4. Verify assertion with WebAuthn
    let verifiedAuthentication = try webAuthn.finishAuthentication(
      credential: credential,
      expectedChallenge: bodyData.challenge.base64decoded(),
      credentialPublicKey: Array(passkeyCredential.publicKey),
      credentialCurrentSignCount: UInt32(passkeyCredential.signCount)
    )

    // 5. Update stored sign counter
    try await database.write { db in
      try await PasskeyCredential
        .update {
          $0.signCount = #sql(
            "GREATEST(\($0.signCount), \(Int64(verifiedAuthentication.newSignCount)))"
          )
        }
        .where { $0.id.eq(verifiedAuthentication.credentialID.asString()) }
        .execute(db)
    }

    // 6. Issue application tokens
    let (token, refreshToken) = try await generateUserToken(
      userID: passkeyCredential.userID
    )

    return .ok(
      .init(
        body: .json(
          .init(
            id: passkeyCredential.userID.uuidString,
            token: token,
            refreshToken: refreshToken
          )
        )
      )
    )
  }
}
