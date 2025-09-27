extension API {
  func getAppleAppSiteAssociation(
    _ input: Operations.GetAppleAppSiteAssociation.Input
  ) async throws -> Operations.GetAppleAppSiteAssociation.Output {
    return .ok(
      .init(
        body: .json(
          .init(
            webcredentials: .init(apps: appleAppSiteAssociation.webcredentials.apps),
            appclips: .init(apps: appleAppSiteAssociation.appclips.apps),
            applinks: .init(
              details: appleAppSiteAssociation.applinks.details.map {
                .init(appIDs: $0.appIdDs, components: [])
              })
          ))))
  }
}
