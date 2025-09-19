import Foundation
import Hummingbird
import HummingbirdPostgres
import Logging
import PostgresMigrations
import PostgresNIO
import Valkey
import WebAuthn
import Crypto

func buildApplication(
  _ arguments: some AppArguments
) async throws -> some ApplicationProtocol {
  let environment = Environment()
  var logger = Logger(label: "App")
  logger.logLevel = .debug

  let valkeyAuthentication: ValkeyClientConfiguration.Authentication?
  if let username = environment.get("VALKEY_USERNAME"),
    let password = environment.get("VALKEY_PASSWORD")
  {
    valkeyAuthentication = ValkeyClientConfiguration.Authentication(
      username: username, password: password)
  } else {
    valkeyAuthentication = nil
  }

  #if DEBUG
  let valkeyTLS: ValkeyClientConfiguration.TLS = .disable
  #else
  let valkeyTLS: ValkeyClientConfiguration.TLS = try .enable(.clientDefault, tlsServerName: environment.require("VALKEY_HOSTNAME"))
  #endif
  
  let cache = try ValkeyClient(
    .hostname(environment.require("VALKEY_HOSTNAME")),
    configuration: .init(
      authentication: valkeyAuthentication,
      tls: valkeyTLS
    ),
    logger: logger
  )
  
  #if DEBUG
  let postgresTLS: PostgresClient.Configuration.TLS = .disable
  #else
  let postgresTLS: PostgresClient.Configuration.TLS = .require(.clientDefault)
  #endif

  let config = try PostgresClient.Configuration(
    host: environment.get("POSTGRES_HOSTNAME")!,
    username: environment.require("POSTGRES_USER"),
    password: environment.require("POSTGRES_PASSWORD"),
    database: environment.require("POSTGRES_DB"),
    tls: postgresTLS
  )

  let databaseClient = PostgresClient(
    configuration: config,
    backgroundLogger: logger
  )

  let migrations = DatabaseMigrations()

  let database = await PostgresPersistDriver(
    client: databaseClient,
    migrations: migrations,
    logger: logger
  )

  let router = Router()
//  router.addRoutes(
//    UsersRouter(cache: cache, database: databaseClient).build(),
//    atPath: "users"
//  )
//  router.addRoutes(
//    MeRouter(cache: cache, database: databaseClient).build(),
//    atPath: "me"
//  )
//  router.addRoutes(
//    SignupRouter(cache: cache, database: databaseClient).build(),
//  )
//
//  router.addRoutes(
//    AppleAppSiteAssosiationRouter(appleAppSiteAssociation: .init(
//      webcredentials: .init(apps: [try environment.require("APPLE_APP_ID")]),
//      appclips: .init(apps: []),
//      applinks: .init(details: []))
//    ).build()
//  )
//  
//  router.addRoutes(
//    PasskeyRouter(
//      cache: cache,
//      database: databaseClient,
//      webAuthn: WebAuthnManager(
//        configuration: .init(
//          relyingPartyID: try environment.require("RELYING_PARTY_ID"),
//          relyingPartyName: try environment.require("RELYING_PARTY_NAME"),
//          relyingPartyOrigin: try environment.require("RELYING_PARTY_ORIGIN")
//        ),
//        challengeGenerator: .init {
//          Array(Data(AES.GCM.Nonce()))
//        }
//      )
//    ).build()
//  )
  let jwtKeyCollection = JWTKeyCollection()
  
  let privateKey = try EdDSA.PrivateKey(
    d: environment.require("EdDSA_PRIVATE_KEY"),
    curve: .ed25519
  )
  
  await jwtKeyCollection.add(eddsa: privateKey)
  let api = API(
    cache: cache,
    database: databaseClient,
    jwtKeyCollection: jwtKeyCollection
  )
  try api.registerHandlers(on: router)
  
  var app = Application(
    router: router,
    configuration: .init(
      address: .hostname(arguments.hostname, port: arguments.port)
    ),
    services: [
      databaseClient,
      database,
      cache,
    ],
    logger: Logger(label: "Server")
  )

  app.beforeServerStarts {
    try await migrations.apply(
      client: databaseClient,
      groups: [.persist],
      logger: Logger(label: "Postgres Migrations"),
      dryRun: false
    )
  }

  return app
}

import OpenAPIHummingbird

struct API: APIProtocol {
  var cache: ValkeyClient
  var database: PostgresClient
  var jwtKeyCollection: JWTKeyCollection
}

import PostgresKit
import JWTKit

struct JWTPayloadData: JWTPayload, Equatable {
  var subject: SubjectClaim
  var expiration: ExpirationClaim
  var userName: String

  func verify(using algorithm: some JWTAlgorithm) async throws {
    try self.expiration.verifyNotExpired()
  }
  
  enum CodingKeys: String, CodingKey {
    case subject = "sub"
    case expiration = "exp"
    case userName = "name"
  }
}

extension API {
  func getMe(_ input: Operations.getMe.Input) async throws -> Operations.getMe.Output {
    let token = ""
    let payload = try await jwtKeyCollection.verify(token, as: JWTPayloadData.self)
    
    return .ok(.init(body: .json(.init(
      id: "",
      token: "",
      refreshToken: ""
    ))))
  }
}

extension API {
  func createUser(
    _ input: Operations.createUser.Input
  ) async throws -> Operations.createUser.Output {
    let user = try await addUserToDatabase()
    
    let tokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)), // 1 hour
      userName: user.id.uuidString
    )
    
    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: user.id.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)), // 1 year
      userName: user.id.uuidString
    )
    
    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)

    return .ok(.init(body: .json(.init(
      id: user.id.uuidString,
      token: token,
      refreshToken: refreshToken
    ))))
  }
  
  func addUserToDatabase() async throws -> User {
    return try await database.withConnection { connection in
      do {
        // 1. Insert into users
        let result = try await connection.query(
          """
            INSERT INTO users (id)
            VALUES (gen_random_uuid())
            RETURNING *
          """,
          logger: Logger(label: "Database INSERT")
        )
        
        let user = try await result.collect().first?.sql().decode(
          model: User.self,
          with: SQLRowDecoder()
        )
        
        guard let user else {
//          self.logger.error("Failed to insert user. Not found user")
          try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
          throw HTTPError(.internalServerError)
        }
        return user
      } catch {
//        self.logger.error(
//          """
//            Failed to insert user
//            Error: \(String(reflecting: error))
//          """)
        try await connection.query("ROLLBACK", logger: Logger(label: "Database ROLLBACK"))
        throw HTTPError(.internalServerError)
      }
    }
  }
}
