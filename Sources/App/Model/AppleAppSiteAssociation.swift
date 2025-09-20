struct AppleAppSiteAssociation: Codable {
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
}
