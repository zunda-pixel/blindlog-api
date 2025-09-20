import Foundation
import Hummingbird
import NIOFoundationCompat
import PostgresKit
import PostgresNIO
import Valkey
import WebAuthn
import Crypto

struct PasskeyRouter<Context: RequestContext> : Sendable {
  var cache: ValkeyClient
  var logger: Logger = Logger(label: "SignUpRouter")
  var database: PostgresClient
  var webAuthn: WebAuthnManager
  
  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .post("addPasskey") { request, context in
        try await verifyPasskey(
          request: request,
          context: context
        )
      }
  }
  
  func verifyPasskey(
    request: Request,
    context: some RequestContext
  ) async throws -> HTTPResponse.Status {
    do {
      guard let userIDString = request.uri.queryParameters["userID"],
            let userID = UUID(uuidString: String(userIDString)) else { throw HTTPError(.badRequest) }
      guard let challenge = request.uri.queryParameters["challenge"] else { throw HTTPError(.badRequest) }
      
      // 1. Verify Challenge is valid.
      let row = try await database.query(
        """
          SELECT * FROM user_challenge
          WHERE user_id = \(userID)
            AND challenge = \(String(challenge))
            AND expired_date > CURRENT_TIMESTAMP
        """
      ).collect().first
      
      guard row != nil else {
        throw HTTPError(.badRequest)
      }
      
      // 2. Verify Client Credential Data and get public key
      let input: RegistrationCredential = try await request.decode(as: RegistrationCredential.self, context: context)

      let credential = try await webAuthn.finishRegistration(
        challenge: Array(Data(base64Encoded: "ToZZ6lNfnNgLKoq+RZio0mYWerIr6T+I2tPOQcVKqEM=")!),
        credentialCreationData: input,
        confirmCredentialIDNotRegisteredYet: { id in
          let row = try await database.query(
            """
              SELECT * FROM user_webauth_credential
              WHERE user_id = \(userID)
                AND credential_id = \(input.id.asString())
            """
          ).collect().first
          return row == nil
        }
      )
      
      // 3. Save PublicKey to DB
      try await database.query(
        """
          INSERT INTO user_webauth_credential (user_id, credential_id, public_key)
          VALUES(\(userID), \(credential.id), \(Data(credential.publicKey).base64EncodedString()))
        """
      )
      
      return .ok
    } catch {
      logger.error(
        """
        Failed to save user
        Error: \(String(reflecting: error))
        """
      )
      throw HTTPError(.internalServerError)
    }
  }
}


