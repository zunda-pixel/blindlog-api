import AsyncHTTPClient
import Configuration
import Crypto
import EmailService
import Foundation
import HTTPClient
import Hummingbird
import Images
import JWTKit
import Logging
import OTel
import OpenAPIHummingbird
import PostgresNIO
import ServiceLifecycle
import Synchronization
import Valkey
import WebAuthn

// LoggingSystem / MetricsSystem / InstrumentationSystem (called transitively
// from OTel.bootstrap) can only be bootstrapped once per process. The test
// suite calls buildApplication multiple times, so the first call performs the
// real bootstrap and subsequent calls return a no-op Service that just waits
// for graceful shutdown. Production only ever calls buildApplication once.
private let observabilityBootstrapped: Mutex<Bool> = .init(false)

struct OTPSecretKeyConfigurationError: Error, CustomStringConvertible {
  var description: String {
    "OTP secret key must be valid Base64"
  }
}

private struct AlreadyBootstrappedObservabilityService: Service {
  func run() async throws {
    try await gracefulShutdown()
  }
}

func buildApplication(
  _ arguments: some AppArguments,
  cloudflareImagesClient: (any CloudflareImagesClientProtocol)? = nil,
  emailService: (any EmailServiceProtocol)? = nil,
  webAuthn: (any WebAuthnProtocol)? = nil
) async throws -> some ApplicationProtocol {
  let config = ConfigReader(providers: [EnvironmentVariablesProvider()])

  let logLevel =
    arguments.logLevel ?? config.string(forKey: "log.level").flatMap { Logger.Level(rawValue: $0) }
    ?? .debug

  // Bootstrap OTel before constructing any Logger: swift-log's `Logger(label:)`
  // captures the LogHandler factory at init time, so a Logger created earlier
  // would silently keep the default StreamLogHandler instead of OTel's handler.
  let observability: any Service = try observabilityBootstrapped.withLock { wasBootstrapped in
    if wasBootstrapped {
      return AlreadyBootstrappedObservabilityService()
    }
    // Only flip the flag once OTel.bootstrap has actually returned a service.
    // If it throws, leave the flag false so the next attempt can retry.
    let service = try OTel.bootstrap(
      configuration: makeOTelConfiguration(
        arguments: arguments,
        config: config,
        logLevel: logLevel
      )
    )
    wasBootstrapped = true
    return service
  }

  var logger = Logger(label: "Blindlog")
  logger.logLevel = logLevel

  let cache = try makeCache(
    arguments: arguments,
    config: config,
    logger: logger
  )

  let databaseClient = try await makeDatabase(
    arguments: arguments,
    config: config,
    logger: logger
  )

  let router = Router(context: AppRequestContext.self)

  let jwtKeyCollection = JWTKeyCollection()
  let privateKey = try EdDSA.PrivateKey(
    d: config.requiredString(forKey: "eddsa.private.key"),
    curve: .ed25519
  )

  await jwtKeyCollection.add(eddsa: privateKey)
  let jwtConfiguration = try makeJWTConfiguration(config: config)

  let api = try API(
    cache: cache,
    database: databaseClient,
    cloudflareImagesClient: cloudflareImagesClient ?? makeCloudflareImagesClient(config: config),
    jwtKeyCollection: jwtKeyCollection,
    jwtConfiguration: jwtConfiguration,
    webAuthn: webAuthn ?? LiveWebAuthn(manager: makeWebAuth(config: config)),
    appleAppSiteAssociation: makeAppleAppSiteAssociation(config: config),
    emailService: emailService ?? makeCloudflareEmailService(config: config),
    otpSecretKey: makeOTPSecretKey(config: config),
    passConfiguration: makePassConfiguration(config: config)
  )

  router.add(
    middleware: TracingMiddleware(
      redactingQueryParameters: [
        "challenge",
        "email",
        "otp",
        "password",
        "refreshToken",
        "token",
      ]
    )
  )
  router.add(middleware: ErrorLoggingMiddleware())
  router.add(middleware: MetricsMiddleware())
  router.add(middleware: LogRequestsMiddleware(.info))
  router.add(middleware: FileMiddleware(searchForIndexHtml: true))

  let apiRouter =
    router
    .group()
    .add(
      middleware: UserTokenMiddleware(
        jwtKeyCollection: jwtKeyCollection,
        jwtConfiguration: jwtConfiguration
      )
    )
    .add(
      middleware: RateLimitMiddleware(
        cache: cache,
        config: try makeRateLimitConfig(arguments: arguments, config: config)
      )
    )
    .add(middleware: OpenAPIRequestContextMiddleware())

  try api.registerHandlers(on: apiRouter)

  let app = Application(
    router: router,
    configuration: .init(
      address: .hostname(arguments.hostname, port: arguments.port)
    ),
    services: [
      observability,
      databaseClient,
      cache,
    ],
    logger: logger
  )

  return app
}

func makeRateLimitConfig(
  arguments: some AppArguments,
  config: ConfigReader
) throws -> RateLimitConfig {
  let config = config.scoped(to: "ratelimit")
  return try RateLimitConfig(
    durationSeconds: arguments.rateLimitDurationSeconds
      ?? config.requiredInt(forKey: "duration.seconds"),
    ipAddressMaxCount: arguments.rateLimitIPAddressMaxCount
      ?? config.requiredInt(forKey: "ip.address.max.count"),
    userTokenMaxCount: arguments.rateLimitUserTokenMaxCount
      ?? config.requiredInt(forKey: "user.token.max.count"),
    authenticationEndpointMaxCount: arguments.rateLimitAuthenticationEndpointMaxCount
      ?? config.int(forKey: "authentication.endpoint.max.count")
      ?? 30
  )
}

func makeJWTConfiguration(config: ConfigReader) throws -> JWTConfiguration {
  try JWTConfiguration(
    issuer: config.requiredString(forKey: "jwt.issuer"),
    audience: config.requiredString(forKey: "jwt.audience"),
  )
}

func makeCache(
  arguments: some AppArguments,
  config: ConfigReader,
  logger: Logger
) throws -> ValkeyClient {
  let valkeyAuthentication: ValkeyClientConfiguration.Authentication? =
    switch arguments.env {
    case .develop:
      nil
    case .production:
      try ValkeyClientConfiguration.Authentication(
        username: config.requiredString(forKey: "valkey.username"),
        password: config.requiredString(forKey: "valkey.password")
      )
    }

  let valkeyTLS: ValkeyClientConfiguration.TLS =
    switch arguments.env {
    case .develop:
      .disable
    case .production:
      try .enable(
        .clientDefault,
        tlsServerName: config.requiredString(forKey: "valkey.hostname")
      )
    }

  return try ValkeyClient(
    .hostname(config.requiredString(forKey: "valkey.hostname")),
    configuration: .init(
      authentication: valkeyAuthentication,
      tls: valkeyTLS
    ),
    logger: logger
  )
}

func makeDatabase(
  arguments: some AppArguments,
  config: ConfigReader,
  logger: Logger
) async throws -> PostgresClient {
  let postgresTLS: PostgresClient.Configuration.TLS =
    switch arguments.env {
    case .develop:
      .disable
    case .production:
      .require(.clientDefault)
    }
  let databaseClient: PostgresClient

  do {
    let config = config.scoped(to: "postgres")
    let postgresConfig = try PostgresClient.Configuration(
      host: config.requiredString(forKey: "hostname"),
      username: config.requiredString(forKey: "user"),
      password: config.requiredString(forKey: "password"),
      database: config.requiredString(forKey: "db"),
      tls: postgresTLS
    )

    databaseClient = PostgresClient(
      configuration: postgresConfig,
      backgroundLogger: logger
    )
  }

  return databaseClient
}

func makeWebAuth(config: ConfigReader) throws -> WebAuthnManager {
  let config = config.scoped(to: "relying.party")

  return try WebAuthnManager(
    configuration: .init(
      relyingPartyID: config.requiredString(forKey: "id"),
      relyingPartyName: config.requiredString(forKey: "name"),
      relyingPartyOrigin: config.requiredString(forKey: "origin")
    )
  )
}

func makeAppleAppSiteAssociation(config: ConfigReader) throws -> AppleAppSiteAssociation {
  try AppleAppSiteAssociation(
    webcredentials: .init(apps: [config.requiredString(forKey: "apple.app.id")]),
    appclips: .init(apps: []),
    applinks: .init(details: [])
  )
}

func makeOTPSecretKey(config: ConfigReader) throws -> SymmetricKey {
  let secretKey = try config.requiredString(forKey: "otp.secret.key")
  guard let secretKeyData = Data(base64Encoded: secretKey) else {
    throw OTPSecretKeyConfigurationError()
  }
  return SymmetricKey(data: secretKeyData)
}

func makePassConfiguration(config: ConfigReader) throws -> PassConfiguration? {
  let config = config.scoped(to: "pass")
  guard
    let certificateBase64 = config.string(forKey: "certificate"),
    let wwdrBase64 = config.string(forKey: "wwdr.certificate"),
    let passTypeIdentifier = config.string(forKey: "type.identifier"),
    let teamIdentifier = config.string(forKey: "team.identifier"),
    let organizationName = config.string(forKey: "organization.name")
  else {
    // Pass signing is optional; without certificates the endpoint is disabled.
    return nil
  }
  guard
    let certificateData = Data(base64Encoded: certificateBase64),
    let wwdrData = Data(base64Encoded: wwdrBase64)
  else {
    throw PassConfigurationError.invalidCertificate
  }

  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("blindlog-pass-certificates", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let passCertificateURL = directory.appendingPathComponent("pass.p12")
  let wwdrCertificateURL = directory.appendingPathComponent("wwdr.cer")
  try certificateData.write(to: passCertificateURL)
  try wwdrData.write(to: wwdrCertificateURL)

  return PassConfiguration(
    passCertificateURL: passCertificateURL,
    passCertificatePassword: config.string(forKey: "certificate.password"),
    wwdrCertificateURL: wwdrCertificateURL,
    passTypeIdentifier: passTypeIdentifier,
    teamIdentifier: teamIdentifier,
    organizationName: organizationName
  )
}

func makeCloudflareEmailService(
  config: ConfigReader
) throws -> EmailService.Client<AsyncHTTPClient.HTTPClient> {
  let config = config.scoped(to: "cloudflare")
  return try .init(
    accountId: config.requiredString(forKey: "account.id"),
    apiToken: config.requiredString(forKey: "api.token"),
    httpClient: .asyncHTTPClient(.shared)
  )
}

func makeCloudflareImagesClient(
  config: ConfigReader
) throws -> any CloudflareImagesClientProtocol {
  let config = config.scoped(to: "cloudflare")
  return CloudflareImagesClient(
    client: Images.Client(
      accountId: try config.requiredString(forKey: "account.id"),
      apiToken: try config.requiredString(forKey: "api.token"),
      httpClient: .asyncHTTPClient(.shared)
    )
  )
}
