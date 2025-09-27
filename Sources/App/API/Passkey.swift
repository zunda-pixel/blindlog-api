import Foundation
import Hummingbird
import OpenAPIRuntime
import PostgresNIO
import Records
import SQLKit
import StructuredQueriesPostgres
import WebAuthn

extension API {
  func addPasskey(
    _ input: Operations.AddPasskey.Input
  ) async throws -> Operations.AddPasskey.Output {
    guard let userID = User.currentUserID else {
      throw HTTPError(.unauthorized)
    }
    // 1. Parse request payload
    guard case .json(let body) = input.body else { throw HTTPError(.badRequest) }
    let registrationCredential: RegistrationCredential
    do {
      let bodyData = try JSONEncoder().encode(body)
      registrationCredential = try JSONDecoder().decode(
        RegistrationCredential.self,
        from: bodyData
      )
    } catch {
      BasicRequestContext.current!.logger.info("""
        Failure to decode WebAuthn registration
        Body: \(body)
        Error: \(error)
      """)
      throw HTTPError(.badRequest)
    }
    // 2. Verify and delete challenge atomically
    let challengeData = Data(input.query.challenge.data)
    do {
      let row = try await database.write { db in
        try await Challenge
          .delete()
          .where {
            $0.challenge.eq(challengeData)
              .and(
                $0.userID.eq(userID)
                  .and(
                    $0.purpose.eq(Challenge.Purpose.registration)
                      .and($0.expiredDate.gt(Date.currentTimestamp))))
          }
          .returning(\.self)
          .fetchOne(db)
      }
      
      guard row != nil else {
        throw HTTPError(.badRequest)
      }
    } catch {
      BasicRequestContext.current!.logger.info("""
        Failure to veryfy and delete challnge atomically
        Challenge: \(challengeData.base64EncodedString())
        Error: \(error)
        """)
      throw HTTPError(.badRequest)
    }

    // 3. Validate WebAuthn registration data
    let credential: Credential
    do {
      credential = try await webAuthn.finishRegistration(
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
    } catch {
      BasicRequestContext.current!.logger.info("""
        Failure to validate WebAuthn registration data
        Challenge: \(registrationCredential)
        Error: \(error)
        """)
      throw HTTPError(.badRequest)
    }
    // 4. Persist credential metadata
    do {
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
    } catch {
      BasicRequestContext.current!.logger.info("""
        Failure to persist credential metadata
        credentail id: \(registrationCredential.id.asString())
        Error: \(error)
        """)
      throw HTTPError(.badRequest)
    }

    return .ok
  }
}
