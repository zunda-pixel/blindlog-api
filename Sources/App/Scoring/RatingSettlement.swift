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
      let lockEvent: QueryFragment =
        "SELECT id FROM public.events WHERE id = \(eventID, as: UUID.self) FOR UPDATE"
      try await db.executeFragment(lockEvent)

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
        let lockQuestion: QueryFragment =
          "SELECT id FROM public.event_questions WHERE id = \(question.id, as: UUID.self) FOR UPDATE"
        try await db.executeFragment(lockQuestion)

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
          let upsert: QueryFragment = """
            INSERT INTO public.user_season_ratings (user_id, season_id, rating, updated_at)
            VALUES (
              \(userID, as: UUID.self),
              \(season.id, as: UUID.self),
              \(initialRating + delta, as: Int.self),
              \(now, as: Date.self)
            )
            ON CONFLICT (user_id, season_id) DO UPDATE
            SET rating = public.user_season_ratings.rating + \(delta, as: Int.self),
                updated_at = EXCLUDED.updated_at
            """
          try await db.executeFragment(upsert)

          let ratingAfter =
            try await UserSeasonRatingRecord
            .where {
              $0.userID.eq(userID)
                .and($0.seasonID.eq(season.id))
            }
            .limit(1)
            .fetchOne(db)?
            .rating ?? (initialRating + delta)

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
    let lockQuestion: QueryFragment =
      "SELECT id FROM public.event_questions WHERE id = \(questionID, as: UUID.self) FOR UPDATE"
    try await db.executeFragment(lockQuestion)

    let entries =
      try await UserRatingLedgerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .fetchAll(db)
    let now = Date()
    for entry in entries {
      let reverse: QueryFragment = """
        UPDATE public.user_season_ratings
        SET rating = rating - \(entry.delta, as: Int.self),
            updated_at = \(now, as: Date.self)
        WHERE user_id = \(entry.userID, as: UUID.self)
          AND season_id = \(entry.seasonID, as: UUID.self)
        """
      try await db.executeFragment(reverse)
    }
    let deleteLedger: QueryFragment =
      "DELETE FROM public.user_rating_ledger WHERE event_question_id = \(questionID, as: UUID.self)"
    try await db.executeFragment(deleteLedger)
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
}
