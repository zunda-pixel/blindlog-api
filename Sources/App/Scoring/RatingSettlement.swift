import Foundation
import ISO_9075_Call_Level_Interface
import ISO_9075_Foundation
import PostgreSQL
import SQL
import SQL_Foundation_Integration
import UUIDV7

enum RatingSettlement {
  static let initialRating = 1000

  static func settle(
    eventID: UUID,
    organizerUserID: UUID,
    answersPublishedAt: Date,
    database: PostgreSQL.Database
  ) async throws {
    try await database.write { (db) throws(ISO_9075.Error) in
      try RowLocks.event(eventID, db: db)

      guard
        let season = try seasonForSettlement(at: answersPublishedAt, db: db)
      else {
        return
      }

      let questions =
        try EventQuestionRecord
        .where { $0.eventID.eq(eventID) }
        .order { $0.questionNumber }
        .fetchAll(db)

      for question in questions {
        try RowLocks.eventQuestion(question.id, db: db)

        let existing =
          try UserRatingLedgerRecord
          .where {
            $0.seasonID.eq(season.id)
              .and($0.eventQuestionID.eq(question.id))
          }
          .limit(1)
          .fetchOne(db)
        if existing != nil { continue }

        let scores =
          try API.scoreQuestion(questionID: question.id, db: db)
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
          let ratingAfter = try applyRatingDelta(
            userID: userID,
            seasonID: season.id,
            delta: delta,
            now: now,
            db: db
          )

          try UserRatingLedgerRecord.insert {
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
    database: PostgreSQL.Database
  ) async throws {
    try await database.write { (db) throws(ISO_9075.Error) in
      try invalidateQuestion(questionID: questionID, db: db)
    }
  }

  static func invalidateQuestion(
    questionID: UUID,
    db: PostgreSQL.Connection
  ) throws(ISO_9075.Error) {
    try RowLocks.eventQuestion(questionID, db: db)

    let entries =
      try UserRatingLedgerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .fetchAll(db)
    let now = Date()
    for entry in entries {
      let existing =
        try UserSeasonRatingRecord
        .where {
          $0.userID.eq(entry.userID)
            .and($0.seasonID.eq(entry.seasonID))
        }
        .limit(1)
        .fetchOne(db)
      guard let existing else { continue }
      try UserSeasonRatingRecord
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
    try UserRatingLedgerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .delete()
      .execute(db)
  }

  static func seasonForSettlement(
    at publishedAt: Date,
    db: PostgreSQL.Connection
  ) throws(ISO_9075.Error) -> RatingSeasonRecord? {
    let seasons =
      try RatingSeasonRecord
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
    db: PostgreSQL.Connection
  ) throws(ISO_9075.Error) -> Int {
    let existing =
      try UserSeasonRatingRecord
      .where {
        $0.userID.eq(userID)
          .and($0.seasonID.eq(seasonID))
      }
      .limit(1)
      .fetchOne(db)

    if let existing {
      let ratingAfter = existing.rating + delta
      try UserSeasonRatingRecord
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
    try UserSeasonRatingRecord.insert {
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
