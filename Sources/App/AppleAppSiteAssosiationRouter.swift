import Hummingbird

struct AppleAppSiteAssociation: Codable, ResponseGenerator {
  let webcredentials: Webcredentials
  
  struct Webcredentials: Codable {
    var apps: [String]
  }
  
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
}

struct AppleAppSiteAssosiationRouter<Context: RequestContext> {
  var appIds: [String]

  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .get("/.well-known/apple-app-site-association") { request, context in
        let credential = AppleAppSiteAssociation(webcredentials: .init(apps: appIds))
        return credential
      }
  }
}
