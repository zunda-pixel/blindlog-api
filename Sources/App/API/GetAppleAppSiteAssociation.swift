extension API {
  func getAppleAppSiteAssociation(
    _ input: Operations.getAppleAppSiteAssociation.Input
  ) async throws -> Operations.getAppleAppSiteAssociation.Output {
    return .ok(
      .init(
        body: .json(
          .init(
            webcredentials: .init(apps: appleAppSiteAssociation.webcredentials.apps),
            appclips: .init(apps: appleAppSiteAssociation.appclips.apps),
            applinks: .init(
              details: appleAppSiteAssociation.applinks.details.map {
                .init(appIdDs: $0.appIdDs, components: [])
              })
          ))))
  }
}
