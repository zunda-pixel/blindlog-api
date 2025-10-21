extension API {
  func getAppleAppSiteAssociation(
    _ input: Operations.GetAppleAppSiteAssociation.Input
  ) async throws -> Operations.GetAppleAppSiteAssociation.Output {
    let appleAppSiteAssociation = Components.Schemas.AppleAppSiteAssociation(
      webcredentials: .init(apps: appleAppSiteAssociation.webcredentials.apps),
      appclips: .init(apps: appleAppSiteAssociation.appclips.apps),
      applinks: .init(
        details: appleAppSiteAssociation.applinks.details.map {
          .init(appIDs: $0.appIdDs, components: [])
        }
      )
    )
    return .ok(.init(body: .json(appleAppSiteAssociation)))
  }
}
