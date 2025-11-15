import Foundation
import HTTPTypes
import Hummingbird
import Valkey

struct RateLimitMiddleware<Context: RequestContext>: RouterMiddleware {
  var cache: ValkeyClient
  var config: RateLimitConfig

  func ipAddress(
    headerFields: HTTPFields
  ) -> String? {
    // Refer to https://github.com/upstash/ratelimit-js for reference and modifications

    // ex) 203.0.113.5, 198.51.100.7, 192.0.2.10
    if let xForwardedFor = headerFields[.xForwardedFor],
      let ipAddress = xForwardedFor.split(separator: ",").first
    {
      return ipAddress.trimmingCharacters(in: .whitespaces)
    }

    // ex) for=\"181.162.191.26\";proto=https
    if let forwarded = headerFields[.forwarded],
      let forPart = forwarded.split(separator: ";").first(where: {
        $0.lowercased().contains("for=")
      })
    {
      return
        forPart
        .replacingOccurrences(of: "for=", with: "", options: .caseInsensitive)
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    if let ipAddress = headerFields[.cfConnectingIP] {
      return ipAddress
    }

    return nil
  }

  func ipAddressAccessCount(ipAddress: String, endpoint: String, timeID: Int) async throws
    -> AccessCount
  {
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
    next: (Request, Context) async throws -> Response
  ) async throws -> Response {
    guard let ipAddress = ipAddress(headerFields: request.headers),
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
  static let xForwardedFor = Self("X-Forwarded-For")!
  static let cfConnectingIP = Self("CF-Connecting-IP")!
  static let forwarded = Self("Forwarded")!
}

struct RateLimitConfig {
  var durationSeconds: Int
  var ipAddressMaxCount: Int
  var userTokenMaxCount: Int
}
