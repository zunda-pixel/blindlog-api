import Foundation
import PostgresNIO
import Records
import StructuredQueriesPostgres
import UUIDV7

enum RatingSettlement {
  static let initialRating = 1000

  static func settle(
    eventID: UUID,
    organizerUserID: UUID,
    answersPublishedAt: Date,
    database: PostgresClient
  ) async throws {
    try await database.withTransaction { db in
      try await RowLocks.event(eventID, db: db)

      guard
        let season = try await seasonForSettlement(at: answersPublishedAt, db: db)
      else {
        return
      }

      let questions =
        try await EventQuestionRecord
        .where { $0.eventID.eq(eventID) }
        .order { $0.questionNumber }
        .fetchAll(db)

      for question in questions {
        try await RowLocks.eventQuestion(question.id, db: db)

        let existing =
          try await UserRatingLedgerRecord
          .where {
            $0.seasonID.eq(season.id)
              .and($0.eventQuestionID.eq(question.id))
          }
          .limit(1)
          .fetchOne(db)
        if existing != nil { continue }

        let scores =
          try await API.scoreQuestion(questionID: question.id, db: db)
          .filter { $0.0 != organizerUserID }
        guard !scores.isEmpty else { continue }
        let average =
          scores.map(\.1.performance).reduce(0, +) / Double(scores.count)

        for (userID, result) in scores {
          let delta = RatingCalculator.delta(
            performance: result.performance,
            fieldAverage: average
          )
          let now = Date()
          let ratingAfter = try await applyRatingDelta(
            userID: userID,
            seasonID: season.id,
            delta: delta,
            now: now,
            db: db
          )

          try await UserRatingLedgerRecord.insert {
            UserRatingLedgerRecord(
              id: UUID(uuidString: UUID.uuidV7String())!,
              userID: userID,
              seasonID: season.id,
              eventQuestionID: question.id,
              performance: result.performance,
              fieldAverage: average,
              delta: delta,
              ratingAfter: ratingAfter,
              createdAt: now
            )
          }.execute(db)
        }
      }
    }
  }

  /// Reverses rating deltas and deletes ledger rows for a question so it can be settled again.
  static func invalidateQuestion(
    questionID: UUID,
    database: PostgresClient
  ) async throws {
    try await database.withTransaction { db in
      try await invalidateQuestion(questionID: questionID, db: db)
    }
  }

  static func invalidateQuestion(
    questionID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws {
    try await RowLocks.eventQuestion(questionID, db: db)

    let entries =
      try await UserRatingLedgerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .fetchAll(db)
    let now = Date()
    for entry in entries {
      let existing =
        try await UserSeasonRatingRecord
        .where {
          $0.userID.eq(entry.userID)
            .and($0.seasonID.eq(entry.seasonID))
        }
        .limit(1)
        .fetchOne(db)
      guard let existing else { continue }
      try await UserSeasonRatingRecord
        .where {
          $0.userID.eq(entry.userID)
            .and($0.seasonID.eq(entry.seasonID))
        }
        .update {
          $0.rating = existing.rating - entry.delta
          $0.updatedAt = now
        }
        .execute(db)
    }
    try await UserRatingLedgerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .delete()
      .execute(db)
  }

  static func seasonForSettlement(
    at publishedAt: Date,
    db: any Database.Connection.`Protocol`
  ) async throws -> RatingSeasonRecord? {
    let seasons =
      try await RatingSeasonRecord
      .order { ($0.startsAt.desc(), $0.id.desc()) }
      .fetchAll(db)
    return seasons.first { season in
      guard season.startsAt <= publishedAt else { return false }
      if let endsAt = season.endsAt {
        return endsAt > publishedAt
      }
      return true
    }
  }

  /// Applies `delta` to the user's season rating and returns the rating after the change.
  private static func applyRatingDelta(
    userID: UUID,
    seasonID: UUID,
    delta: Int,
    now: Date,
    db: any Database.Connection.`Protocol`
  ) async throws -> Int {
    let existing =
      try await UserSeasonRatingRecord
      .where {
        $0.userID.eq(userID)
          .and($0.seasonID.eq(seasonID))
      }
      .limit(1)
      .fetchOne(db)

    if let existing {
      let ratingAfter = existing.rating + delta
      try await UserSeasonRatingRecord
        .where {
          $0.userID.eq(userID)
            .and($0.seasonID.eq(seasonID))
        }
        .update {
          $0.rating = ratingAfter
          $0.updatedAt = now
        }
        .execute(db)
      return ratingAfter
    }

    let ratingAfter = initialRating + delta
    try await UserSeasonRatingRecord.insert {
      UserSeasonRatingRecord(
        userID: userID,
        seasonID: seasonID,
        rating: ratingAfter,
        updatedAt: now
      )
    }.execute(db)
    return ratingAfter
  }
}
