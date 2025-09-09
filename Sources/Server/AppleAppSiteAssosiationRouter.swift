import Hummingbird

struct WebCredential: Codable, ResponseGenerator {
  func response(
    from request: HummingbirdCore.Request,
    context: some Hummingbird.RequestContext
  ) throws -> HummingbirdCore.Response {
    try context.responseEncoder.encode(
      self,
      from: request,
      context: context
    )
  }

  let apps: [String]
}

struct AppleAppSiteAssosiationRouter<Context: RequestContext> {
  var appIds: [String]

  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .get("/.well-known/apple-app-site-association") { request, context in
        let credential = WebCredential(apps: appIds)
        return credential
      }
  }
}
