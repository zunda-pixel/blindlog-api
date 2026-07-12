import Foundation
import PostgresNIO
import Records
import StructuredQueriesPostgres
import UUIDV7

extension API {
  func getEventScores(
    _ input: Operations.GetEventScores.Input
  ) async throws -> Operations.GetEventScores.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard let eventID = UUID(uuidString: input.path.eventId) else { return .badRequest }

    do {
      guard let event = try await latestEventSnapshot(eventID: eventID),
        try await canViewEvent(event, userID: userID)
      else {
        return .notFound
      }
      let isOrganizer = event.event.organizerUserID == userID
      guard isOrganizer || Date() >= event.revision.answersPublishedAt else {
        return .forbidden
      }
      try await settleEventRatingsIfNeeded(eventID: eventID)

      let scored = try await scoreEventParticipants(eventID: eventID)
      let payload = scored.map { userID, questions in
        let totalEarned = questions.reduce(0) { $0 + $1.result.earnedPoints }
        let totalMax = questions.reduce(0) { $0 + $1.result.maxPoints }
        return Components.Schemas.EventParticipantScore(
          userID: userID.uuidString,
          totalEarnedPoints: Int32(totalEarned),
          totalMaxPoints: Int32(totalMax),
          questionScores: questions.map { questionID, result in
            Components.Schemas.QuestionScoreSummary(
              eventQuestionID: questionID.uuidString,
              earnedPoints: Int32(result.earnedPoints),
              maxPoints: Int32(result.maxPoints),
              performance: result.performance
            )
          }
        )
      }
      return .ok(.init(body: .json(payload)))
    } catch {
      logEventDatabaseError(
        "event.scores_failed",
        "Failed to fetch event scores",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func getEventLeaderboard(
    _ input: Operations.GetEventLeaderboard.Input
  ) async throws -> Operations.GetEventLeaderboard.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard let eventID = UUID(uuidString: input.path.eventId) else { return .badRequest }

    do {
      guard let event = try await latestEventSnapshot(eventID: eventID),
        try await canViewEvent(event, userID: userID)
      else {
        return .notFound
      }
      let isOrganizer = event.event.organizerUserID == userID
      guard isOrganizer || Date() >= event.revision.answersPublishedAt else {
        return .forbidden
      }
      try await settleEventRatingsIfNeeded(eventID: eventID)

      let scored = try await scoreEventParticipants(eventID: eventID)
      let ranked =
        scored
        .map { userID, questions in
          (
            userID: userID,
            earned: questions.reduce(0) { $0 + $1.result.earnedPoints },
            max: questions.reduce(0) { $0 + $1.result.maxPoints }
          )
        }
        .sorted {
          if $0.earned != $1.earned { return $0.earned > $1.earned }
          return $0.userID.uuidString < $1.userID.uuidString
        }
      var entries: [Components.Schemas.EventLeaderboardEntry] = []
      var rank: Int32 = 1
      for row in ranked {
        entries.append(
          .init(
            rank: rank,
            userID: row.userID.uuidString,
            totalEarnedPoints: Int32(row.earned),
            totalMaxPoints: Int32(row.max)
          )
        )
        rank += 1
      }
      return .ok(.init(body: .json(entries)))
    } catch {
      logEventDatabaseError(
        "event.leaderboard_failed",
        "Failed to fetch event leaderboard",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }

  func getEventQuestionScores(
    _ input: Operations.GetEventQuestionScores.Input
  ) async throws -> Operations.GetEventQuestionScores.Output {
    guard let userID = UserTokenContext.currentUserID else { return .unauthorized }
    guard
      let eventID = UUID(uuidString: input.path.eventId),
      let questionID = UUID(uuidString: input.path.questionId)
    else {
      return .badRequest
    }

    do {
      guard let event = try await latestEventSnapshot(eventID: eventID),
        try await canViewEvent(event, userID: userID),
        try await eventQuestionExists(questionID: questionID, eventID: eventID)
      else {
        return .notFound
      }
      let isOrganizer = event.event.organizerUserID == userID
      guard isOrganizer || Date() >= event.revision.answersPublishedAt else {
        return .forbidden
      }
      try await settleEventRatingsIfNeeded(eventID: eventID)

      let questionScores = try await scoreQuestion(eventID: eventID, questionID: questionID)
      let payload = questionScores.map { userID, result in
        Components.Schemas.EventQuestionUserScore(
          userID: userID.uuidString,
          earnedPoints: Int32(result.earnedPoints),
          maxPoints: Int32(result.maxPoints),
          performance: result.performance,
          components: result.components.map { component in
            Components.Schemas.ScoreComponentResult(
              component: .init(rawValue: component.component.rawValue)!,
              earnedPoints: Int32(component.earnedPoints),
              maxPoints: Int32(component.maxPoints)
            )
          }
        )
      }
      return .ok(.init(body: .json(payload)))
    } catch {
      logEventDatabaseError(
        "event.question_scores_failed",
        "Failed to fetch question scores",
        userID: userID,
        error: error
      )
      return .badRequest
    }
  }
}

extension API {
  func settleEventRatingsIfNeeded(eventID: UUID) async throws {
    guard let event = try await latestEventSnapshot(eventID: eventID) else { return }
    guard Date() >= event.revision.answersPublishedAt else { return }
    try await RatingSettlement.settle(eventID: eventID, database: database)
  }

  func scoreEventParticipants(
    eventID: UUID
  ) async throws -> [(UUID, [(questionID: UUID, result: QuestionScoreResult)])] {
    let questions = try await latestEventQuestionSnapshots(eventID: eventID)
    var byUser: [UUID: [(questionID: UUID, result: QuestionScoreResult)]] = [:]
    for question in questions {
      let scores = try await scoreQuestion(eventID: eventID, questionID: question.question.id)
      for (userID, result) in scores {
        byUser[userID, default: []].append((question.question.id, result))
      }
    }
    return byUser.keys.sorted { $0.uuidString < $1.uuidString }.map { userID in
      (userID, byUser[userID] ?? [])
    }
  }

  func scoreQuestion(
    eventID: UUID,
    questionID: UUID
  ) async throws -> [(UUID, QuestionScoreResult)] {
    try await database.read { db in
      try await Self.scoreQuestion(questionID: questionID, db: db)
    }
  }

  static func scoreQuestion(
    questionID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws -> [(UUID, QuestionScoreResult)] {
    let correct =
      try await EventQuestionCorrectAnswerRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .limit(1)
      .fetchOne(db)
    guard let correct else { return [] }

    let correctRevision =
      try await EventQuestionCorrectAnswerRevisionRecord
      .where { $0.eventQuestionCorrectAnswerID.eq(correct.id) }
      .order { ($0.createdAt.desc(), $0.id.desc()) }
      .limit(1)
      .fetchOne(db)
    guard let correctRevision else { return [] }

    let correctVarieties =
      try await EventQuestionCorrectAnswerVarietyRecord
      .where { $0.eventQuestionCorrectAnswerRevisionID.eq(correctRevision.id) }
      .fetchAll(db)
      .map(\.wineVarietyID)

    let regionRules =
      try await EventQuestionRegionScoreRuleRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .fetchAll(db)
    let componentRules =
      try await EventQuestionScoreComponentRuleRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .fetchAll(db)

    let correctAncestors = try await regionAncestors(
      regionID: correctRevision.wineRegionID,
      db: db
    )
    let correctPayload = ScoringAnswerPayload(
      wineRegionID: correctRevision.wineRegionID,
      producerWineRegionID: correctRevision.producerWineRegionID,
      feature: correctRevision.feature,
      vintage: correctRevision.vintage,
      alcoholByVolume: correctRevision.alcoholByVolume,
      wineVarietyIDs: Set(correctVarieties)
    )

    let responses =
      try await EventQuestionResponseRecord
      .where { $0.eventQuestionID.eq(questionID) }
      .fetchAll(db)

    var results: [(UUID, QuestionScoreResult)] = []
    for response in responses {
      let revision =
        try await EventQuestionResponseRevisionRecord
        .where { $0.eventQuestionResponseID.eq(response.id) }
        .order { ($0.submittedAt.desc(), $0.id.desc()) }
        .limit(1)
        .fetchOne(db)
      guard let revision else { continue }
      let varieties =
        try await EventQuestionResponseVarietyRecord
        .where { $0.eventQuestionResponseRevisionID.eq(revision.id) }
        .fetchAll(db)
        .map(\.wineVarietyID)
      let responseAncestors = try await regionAncestors(regionID: revision.wineRegionID, db: db)
      let responsePayload = ScoringAnswerPayload(
        wineRegionID: revision.wineRegionID,
        producerWineRegionID: revision.producerWineRegionID,
        feature: revision.feature,
        vintage: revision.vintage,
        alcoholByVolume: revision.alcoholByVolume,
        wineVarietyIDs: Set(varieties)
      )
      let score = QuestionScorer.score(
        correct: correctPayload,
        response: responsePayload,
        regionRules: regionRules,
        componentRules: componentRules,
        correctRegionAncestors: correctAncestors,
        responseRegionAncestors: responseAncestors
      )
      results.append((response.userID, score))
    }
    return results.sorted { $0.0.uuidString < $1.0.uuidString }
  }

  static func regionAncestors(
    regionID: UUID?,
    db: any Database.Connection.`Protocol`
  ) async throws -> [RegionAncestor] {
    guard var currentID = regionID else { return [] }
    var ancestors: [RegionAncestor] = []
    var seen = Set<UUID>()
    while seen.insert(currentID).inserted {
      let region = try await WineRegionRecord.where { $0.id.eq(currentID) }.limit(1).fetchOne(db)
      guard let region else { break }
      ancestors.append(RegionAncestor(id: region.id, wineRegionTypeID: region.wineRegionTypeID))
      guard let parent = region.parentRegionID else { break }
      currentID = parent
    }
    return ancestors
  }

  func regionAncestors(
    regionID: UUID?,
    db: any Database.Connection.`Protocol`
  ) async throws -> [RegionAncestor] {
    try await Self.regionAncestors(regionID: regionID, db: db)
  }
}

enum RatingSettlement {
  static let initialRating = 1000

  static func settle(
    eventID: UUID,
    database: PostgresClient
  ) async throws {
    try await database.withTransaction { db in
      let season =
        try await RatingSeasonRecord
        .where { $0.endsAt.is(nil) }
        .order { ($0.startsAt.desc(), $0.id.desc()) }
        .limit(1)
        .fetchOne(db)
      guard let season else { return }

      let questions =
        try await EventQuestionRecord
        .where { $0.eventID.eq(eventID) }
        .order { $0.questionNumber }
        .fetchAll(db)

      for question in questions {
        let existing =
          try await UserRatingLedgerRecord
          .where {
            $0.seasonID.eq(season.id)
              .and($0.eventQuestionID.eq(question.id))
          }
          .limit(1)
          .fetchOne(db)
        if existing != nil { continue }

        let scores = try await API.scoreQuestion(questionID: question.id, db: db)
        guard !scores.isEmpty else { continue }
        let average =
          scores.map(\.1.performance).reduce(0, +) / Double(scores.count)

        for (userID, result) in scores {
          let delta = RatingCalculator.delta(
            performance: result.performance,
            fieldAverage: average
          )
          let current =
            try await UserSeasonRatingRecord
            .where {
              $0.userID.eq(userID)
                .and($0.seasonID.eq(season.id))
            }
            .limit(1)
            .fetchOne(db)
          let ratingBefore = current?.rating ?? initialRating
          let ratingAfter = ratingBefore + delta
          let now = Date()
          if current != nil {
            let updateQuery: QueryFragment = """
              UPDATE public.user_season_ratings
              SET rating = \(ratingAfter, as: Int.self),
                  updated_at = \(now, as: Date.self)
              WHERE user_id = \(userID, as: UUID.self)
                AND season_id = \(season.id, as: UUID.self)
              """
            try await db.executeFragment(updateQuery)
          } else {
            try await UserSeasonRatingRecord.insert {
              UserSeasonRatingRecord(
                userID: userID,
                seasonID: season.id,
                rating: ratingAfter,
                updatedAt: now
              )
            }.execute(db)
          }
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
}
