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
    jwtKeyCollection: jwtKeyCollection,
    appleAppSiteAssociation: .init(
      webcredentials: .init(apps: [try environment.require("APPLE_APP_ID")]),
      appclips: .init(apps: []),
      applinks: .init(details: [])
    )
  )
  router.add(middleware: BearerTokenMiddleware(jwtKeyCollection: jwtKeyCollection, database: databaseClient))
  
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
  var appleAppSiteAssociation: AppleAppSiteAssociation
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
  func generateUserToken(
    userID: UUID
  ) async throws -> (token: String, refreshToken: String) {
    let tokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 1 * 60 * 60)), // 1 hour
      userName: userID.uuidString
    )
    
    let refreshTokenPayload = JWTPayloadData(
      subject: .init(value: userID.uuidString),
      expiration: .init(value: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)), // 1 year
      userName: userID.uuidString
    )
    
    let token = try await jwtKeyCollection.sign(tokenPayload)
    let refreshToken = try await jwtKeyCollection.sign(refreshTokenPayload)
    
    return (token, refreshToken)
  }
  
  func refreshToken(
    _ input: Operations.refreshToken.Input
  ) async throws -> Operations.refreshToken.Output {
    guard case .json(let body) = input.body else {
      throw HTTPError(.unauthorized)
    }
    
    let payload = try await jwtKeyCollection.verify(body.refreshToken, as: JWTPayloadData.self)
    
    guard let userID = UUID(uuidString: payload.subject.value) else {
//      context.logger.debug("Invalid JWT subject \(payload.subject.value)")
      throw HTTPError(.unauthorized)
    }
    // verify expiration is not over.
    guard payload.expiration.value > Date() else {
//      context.logger.debug("Token expired")
      throw HTTPError(.unauthorized)
    }
    
    let (token, refreshToken) = try await generateUserToken(userID: userID)
    
    return .ok(.init(body: .json(.init(
      id: userID.uuidString,
      token: token,
      refreshToken: refreshToken
    ))))
  }
}

extension API {
  func getAppleAppSiteAssociation(
    _ input: Operations.getAppleAppSiteAssociation.Input
  ) async throws -> Operations.getAppleAppSiteAssociation.Output {
    return .ok(.init(body: .json(.init(
      webcredentials: .init(apps: appleAppSiteAssociation.webcredentials.apps),
      appclips: .init(apps: appleAppSiteAssociation.appclips.apps),
      applinks: .init(details: appleAppSiteAssociation.applinks.details.map {
        .init(appIdDs: $0.appIdDs, components: [])
      })
    ))))
  }
}

extension API {
  func getUsers(
    _ input: Operations.getUsers.Input
  ) async throws -> Operations.getUsers.Output {
    let ids:[UUID] = input.query.ids.compactMap { UUID(uuidString: $0) }

    do {
      // 1. Get Users from Cache and Update Expiration if exits
      let cacheUsers = try await getUsersFromCacheAndUpdateExpiration(
        ids: ids
      )

      // 2. Get Users from DB that is not in Cache
      let leftUserIDs = Set(ids).subtracting(Set(cacheUsers.map(\.id)))
      let dbUsers: [User] = try await getUsersFromDatabase(
        ids: Array(leftUserIDs)
      )

      // 3. Set New Users Dat to Cache
      try await addUsersToCache(
        users: dbUsers
      )
      
      let users = cacheUsers + dbUsers
      
      return .ok(.init(body: .json(users.map {
        .init(id: $0.id.uuidString)
      })))
    } catch {
//      logger.error(
//        """
//        Failed to fetch users: \(ids.map(\.uuidString).formatted(.list(type: .and)))
//        Error: \(String(reflecting: error))
//        """
//      )
      throw HTTPError(.internalServerError)
    }
  }
  
  func addUsersToCache(
    users: [User]
  ) async throws {
    let encoder = JSONEncoder()

    try await cache.withConnection { connection in
      try await connection.multi()
      for user in users {
        try await connection.set(
          ValkeyKey("user:\(user.id.uuidString)"),
          value: try encoder.encode(user),
          expiration: .seconds(60 * 10)  // 10 minutes
        )
      }
      try await connection.exec()
    }
  }
  
  func getUsersFromDatabase(
    ids: [User.ID]
  ) async throws -> [User] {
    let query: PostgresQuery = """
        SELECT id
        FROM users
        WHERE users.id = ANY(\(ids))
      """
    let rows = try await database.query(query).collect()

    let decoder = SQLRowDecoder()
    let users: [User] = try rows.map { row in
      return try row.sql().decode(model: User.self, with: decoder)
    }
    return users
  }
  
  func getUsersFromCacheAndUpdateExpiration(
    ids: [User.ID]
  ) async throws -> [User] {
    return try await cache.withConnection { connection in
      return try await withThrowingTaskGroup(of: Optional<User>.self) { group in
        let decoder = JSONDecoder()

        for id in ids {
          group.addTask {
            let userData = try await connection.getex(
              ValkeyKey("user:\(id.uuidString)"),
              expiration: .seconds(60 * 10)  // 10 minutes
            )

            if let userData {
              return try decoder.decode(User.self, from: userData)
            } else {
              return nil
            }
          }
        }

        var users: [User] = []

        for try await user in group {
          guard let user else { continue }
          users.append(user)
        }

        return users
      }
    }
  }
}

extension API {
  func getMe(_ input: Operations.getMe.Input) async throws -> Operations.getMe.Output {
    guard let userID = BearerAuthenticateUser.current?.userID else {
      throw HTTPError(.unauthorized)
    }
    
    let user = try await getUser(id: userID)
    
    return .ok(.init(body: .json(.init(
      id: user.id.uuidString
    ))))
  }
  
  func getUser(id: UUID) async throws -> User {
    // 1. Get User from Cache and Update Expiration if exits
    let cacheUser = try await getUserFromCacheAndUpdateExpiration(
      id: id
    )

    if let cacheUser {
      return cacheUser
    }

    // 2. Get User from DB that is not in Cache
    let dbUser: User? = try await getUserFromDatabase(
      id: id
    )

    guard let dbUser else { throw HTTPError(.notFound) }

    // 3. Set New User to Cache
    try await addUserToCache(
      user: dbUser
    )
    return dbUser
  }
  
  func addUserToCache(
    user: User
  ) async throws {
    try await cache.set(
      ValkeyKey("user:\(user.id.uuidString)"),
      value: try JSONEncoder().encode(user),
      expiration: .seconds(60 * 10)  // 10 minutes
    )
  }
  
  func getUserFromDatabase(
    id: User.ID
  ) async throws -> User? {
    let query: PostgresQuery = """
        SELECT id
        FROM users
        WHERE users.id = \(id)
        LIMIT 1
      """
    let rows = try await database.query(query).collect()

    if let row = rows.first {
      return try row.sql().decode(model: User.self, with: SQLRowDecoder())
    } else {
      return nil
    }
  }
  
  func getUserFromCacheAndUpdateExpiration(
    id: User.ID
  ) async throws -> User? {
    let userData = try await cache.getex(
      ValkeyKey("user:\(id.uuidString)"),
      expiration: .seconds(60 * 10)  // 10 minutes
    )

    if let userData {
      return try JSONDecoder().decode(User.self, from: userData)
    } else {
      return nil
    }
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
