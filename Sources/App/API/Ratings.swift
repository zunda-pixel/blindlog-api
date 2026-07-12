import Foundation
import PostgresNIO
import Records
import StructuredQueriesPostgres
import UUIDV7

extension API {
  func getMyRating(
    _ input: Operations.GetMyRating.Input
  ) async throws -> Operations.GetMyRating.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }

    do {
      guard let season = try await activeRatingSeason() else {
        return .notFound
      }
      let rating =
        try await database.read { db in
          try await UserSeasonRatingRecord
            .where {
              $0.userID.eq(userID)
                .and($0.seasonID.eq(season.id))
            }
            .limit(1)
            .fetchOne(db)
        }?.rating ?? RatingSettlement.initialRating

      let ledger =
        try await database.read { db in
          try await UserRatingLedgerRecord
            .where {
              $0.userID.eq(userID)
                .and($0.seasonID.eq(season.id))
            }
            .order { ($0.createdAt.desc(), $0.id.desc()) }
            .limit(50)
            .fetchAll(db)
        }

      return .ok(
        .init(
          body: .json(
            Components.Schemas.UserRating(
              seasonID: season.id.uuidString,
              seasonName: season.name,
              rating: Int32(rating),
              recentLedger: ledger.map { entry in
                Components.Schemas.RatingLedgerEntry(
                  id: entry.id.uuidString,
                  eventQuestionID: entry.eventQuestionID.uuidString,
                  performance: entry.performance,
                  fieldAverage: entry.fieldAverage,
                  delta: Int32(entry.delta),
                  ratingAfter: Int32(entry.ratingAfter),
                  createdAt: entry.createdAt.timeIntervalSinceReferenceDate
                )
              }
            )
          )
        )
      )
    } catch {
      logEventDatabaseError(
        "rating.me_failed",
        "Failed to fetch user rating",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func getRatingLeaderboard(
    _ input: Operations.GetRatingLeaderboard.Input
  ) async throws -> Operations.GetRatingLeaderboard.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }

    do {
      let season: RatingSeasonRecord?
      if let seasonIDString = input.query.seasonId {
        guard let seasonID = UUID(uuidString: seasonIDString) else { return .badRequest }
        season = try await database.read { db in
          try await RatingSeasonRecord.where { $0.id.eq(seasonID) }.limit(1).fetchOne(db)
        }
      } else {
        season = try await activeRatingSeason()
      }
      guard let season else { return .notFound }

      let rows = try await database.read { db in
        try await UserSeasonRatingRecord
          .where { $0.seasonID.eq(season.id) }
          .order { ($0.rating.desc(), $0.userID) }
          .limit(100)
          .fetchAll(db)
      }

      let entries = Ranking.competitionRanks(rows) { $0.rating }.map { rank, row in
        Components.Schemas.RatingLeaderboardEntry(
          rank: rank,
          userID: row.userID.uuidString,
          rating: Int32(row.rating)
        )
      }
      return .ok(.init(body: .json(entries)))
    } catch {
      logEventDatabaseError(
        "rating.leaderboard_failed",
        "Failed to fetch rating leaderboard",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func createRatingSeason(
    _ input: Operations.CreateRatingSeason.Input
  ) async throws -> Operations.CreateRatingSeason.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard case .json(let body) = input.body else { return .badRequest }
    let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return .badRequest }
    guard isAdminUser(userID) else { return .forbidden }

    do {
      let now = Date()
      let season = try await database.withTransaction { db -> RatingSeasonRecord in
        let active =
          try await RatingSeasonRecord
          .where { $0.endsAt.is(nil) }
          .order { ($0.startsAt.desc(), $0.id.desc()) }
          .limit(1)
          .fetchOne(db)
        if let active {
          try await RatingSeasonRecord
            .where { $0.id.eq(active.id) }
            .update { $0.endsAt = Optional.some(now) }
            .execute(db)
        }
        let season = RatingSeasonRecord(
          id: UUID(uuidString: UUID.uuidV7String())!,
          name: name,
          startsAt: now,
          endsAt: nil,
          createdAt: now
        )
        try await RatingSeasonRecord.insert { season }.execute(db)
        return season
      }
      return .ok(
        .init(
          body: .json(
            Components.Schemas.RatingSeason(
              id: season.id.uuidString,
              name: season.name,
              startsAt: season.startsAt.timeIntervalSinceReferenceDate,
              endsAt: season.endsAt?.timeIntervalSinceReferenceDate,
              createdAt: season.createdAt.timeIntervalSinceReferenceDate
            )
          )
        )
      )
    } catch {
      logEventDatabaseError(
        "rating.season_create_failed",
        "Failed to create rating season",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func activeRatingSeason() async throws -> RatingSeasonRecord? {
    try await database.read { db in
      try await RatingSeasonRecord
        .where { $0.endsAt.is(nil) }
        .order { ($0.startsAt.desc(), $0.id.desc()) }
        .limit(1)
        .fetchOne(db)
    }
  }

  func isAdminUser(_ userID: UUID) -> Bool {
    let raw = ProcessInfo.processInfo.environment["ADMIN_USER_IDS"] ?? ""
    let allowed = raw.split(separator: ",").compactMap {
      UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return allowed.contains(userID)
  }
}
