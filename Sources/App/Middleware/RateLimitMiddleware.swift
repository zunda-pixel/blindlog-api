import Foundation
import HTTPTypes
import Hummingbird
import Valkey

struct RateLimitMiddleware<Context: RequestContext>: RouterMiddleware {
  var cache: ValkeyClient
  var config: RateLimitConfig

  // Trust boundary is enforced at the network layer:
  //   - Cloud Armor allowlist limits ingress to Cloudflare proxy IPs
  //   - Cloud Run ingress = INTERNAL_LOAD_BALANCER blocks *.run.app direct hits
  // Once both are in place, the only path to this code is Cloudflare → GCP LB,
  // and Cloudflare unconditionally sets CF-Connecting-IP with the real client IP.
  // X-Forwarded-For and Forwarded are intentionally ignored: they are spoofable
  // by any caller and the network boundary already provides the proxy guarantee.
  func ipAddress(
    headerFields: HTTPFields,
    context: Context
  ) -> String? {
    if let ipAddress = headerFields[.cfConnectingIP] {
      return ipAddress
    }

    if let remoteAddress = (context as? any RemoteAddressRequestContext)?.remoteAddress,
      let ipAddress = remoteAddress.ipAddress
    {
      return ipAddress
    }

    return nil
  }

  func ipAddressAccessCount(
    ipAddress: String,
    endpoint: String,
    timeID: Int
  ) async throws -> AccessCount {
    let allCount: Int = try await cache.incr(ValkeyKey("AccessCount:\(ipAddress):\(timeID)")) - 1
    let perEndpointCount: Int =
      try await cache.incr(ValkeyKey("AccessCount:\(ipAddress):\(endpoint):\(timeID)")) - 1

    if allCount == 0 {
      try await cache.expire(
        ValkeyKey("AccessCount:\(ipAddress):\(timeID)"),
        seconds: config.durationSeconds
      )
    }
    if perEndpointCount == 0 {
      try await cache.expire(
        ValkeyKey("AccessCount:\(ipAddress):\(endpoint):\(timeID)"),
        seconds: config.durationSeconds
      )
    }

    return AccessCount(
      allCount: allCount,
      perEndpointCount: perEndpointCount
    )
  }

  func userTokenAccessCount(endpoint: String, timeID: Int) async throws -> AccessCount? {
    guard let userID = UserTokenContext.currentUserID else { return nil }

    let allCount: Int = try await cache.incr(ValkeyKey("AccessCount:\(userID):\(timeID)")) - 1
    let perEndpointCount: Int =
      try await cache.incr(ValkeyKey("AccessCount:\(userID):\(endpoint):\(timeID)")) - 1

    if allCount == 0 {
      try await cache.expire(
        ValkeyKey("AccessCount:\(userID):\(timeID)"),
        seconds: config.durationSeconds
      )
    }
    if perEndpointCount == 0 {
      try await cache.expire(
        ValkeyKey("AccessCount:\(userID):\(endpoint):\(timeID)"),
        seconds: config.durationSeconds
      )
    }

    return AccessCount(
      allCount: allCount,
      perEndpointCount: perEndpointCount
    )
  }

  func handle(
    _ request: Request,
    context: Context,
    next: @concurrent (Request, Context) async throws -> Response
  ) async throws -> Response {
    guard let ipAddress = ipAddress(headerFields: request.headers, context: context),
      let endpointPath = request.head.path.flatMap({ URL(string: $0) })?.relativePath
    else {
      throw HTTPError(.badRequest)
    }
    let timeID = Int(Date.now.timeIntervalSinceReferenceDate) / config.durationSeconds
    let ipAddressAccessCount = try await ipAddressAccessCount(
      ipAddress: ipAddress,
      endpoint: endpointPath,
      timeID: timeID
    )

    let userTokenAccessCount: AccessCount? = try await userTokenAccessCount(
      endpoint: endpointPath,
      timeID: timeID
    )
    if let userTokenAllCount = userTokenAccessCount?.allCount {
      if config.userTokenMaxCount <= userTokenAllCount {
        throw HTTPError(.tooManyRequests)
      }
    } else if config.ipAddressMaxCount <= ipAddressAccessCount.allCount {
      throw HTTPError(.tooManyRequests)
    }

    return try await RateLimitContext.$ipAddressAccessCount.withValue(
      ipAddressAccessCount.perEndpointCount
    ) {
      try await RateLimitContext.$userTokenAccessCount.withValue(
        userTokenAccessCount?.perEndpointCount
      ) {
        try await next(request, context)
      }
    }
  }
}

enum RateLimitContext {
  /// Access count per ip address
  @TaskLocal static var ipAddressAccessCount: Int?

  /// Access count per user token
  @TaskLocal static var userTokenAccessCount: Int?
}

struct AccessCount {
  var allCount: Int
  var perEndpointCount: Int
}

extension HTTPField.Name {
  static let cfConnectingIP = Self("CF-Connecting-IP")!
}

struct RateLimitConfig {
  var durationSeconds: Int
  var ipAddressMaxCount: Int
  var userTokenMaxCount: Int
}
