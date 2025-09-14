import Hummingbird

struct AppleAppSiteAssociation: Codable, ResponseGenerator {
  let webcredentials: Webcredentials
  let appclips: AppClips
  var applinks: AppLinks
  struct Webcredentials: Codable {
    var apps: [String]
  }
  
  struct AppClips: Codable {
    var apps: [String]
  }
  
  struct AppLinks: Codable {
    var details: [Detail]
    
    struct Detail: Codable {
      var appIdDs: [String]
      var components: [Component]
      
      struct Component: Codable {
      }
    }
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
  var appleAppSiteAssociation: AppleAppSiteAssociation

  func build() -> RouteCollection<Context> {
    return RouteCollection(context: Context.self)
      .get("/.well-known/apple-app-site-association") { _, _ in
        appleAppSiteAssociation
      }
  }
}
