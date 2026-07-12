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
      guard try await canAccessEventScores(event, userID: userID) else {
        return .forbidden
      }
      try await settleEventRatingsIfNeeded(eventID: eventID)

      let scored = try await scoreEventParticipants(eventID: eventID)
      let payload = scored.map { scoredUserID, questions in
        let totalEarned = questions.reduce(0) { $0 + $1.result.earnedPoints }
        let totalMax = questions.reduce(0) { $0 + $1.result.maxPoints }
        return Components.Schemas.EventParticipantScore(
          userID: scoredUserID.uuidString,
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
      guard try await canAccessEventScores(event, userID: userID) else {
        return .forbidden
      }
      try await settleEventRatingsIfNeeded(eventID: eventID)

      let scored = try await scoreEventParticipants(eventID: eventID)
      let ranked =
        scored
        .map { scoredUserID, questions in
          (
            userID: scoredUserID,
            earned: questions.reduce(0) { $0 + $1.result.earnedPoints },
            max: questions.reduce(0) { $0 + $1.result.maxPoints }
          )
        }
        .sorted {
          if $0.earned != $1.earned { return $0.earned > $1.earned }
          return $0.userID.uuidString < $1.userID.uuidString
        }
      let entries = Ranking.competitionRanks(ranked) { $0.earned }.map { rank, row in
        Components.Schemas.EventLeaderboardEntry(
          rank: rank,
          userID: row.userID.uuidString,
          totalEarnedPoints: Int32(row.earned),
          totalMaxPoints: Int32(row.max)
        )
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
      guard try await canAccessEventScores(event, userID: userID) else {
        return .forbidden
      }
      try await settleEventRatingsIfNeeded(eventID: eventID)

      let questionScores = try await scoreQuestion(eventID: eventID, questionID: questionID)
      let payload = questionScores.map { scoredUserID, result in
        Components.Schemas.EventQuestionUserScore(
          userID: scoredUserID.uuidString,
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
  func canAccessEventScores(_ event: EventSnapshot, userID: UUID) async throws -> Bool {
    if event.event.organizerUserID == userID {
      return true
    }
    guard Date() >= event.revision.answersPublishedAt else {
      return false
    }
    return try await activeParticipantExists(eventID: event.event.id, userID: userID)
  }

  func settleEventRatingsIfNeeded(eventID: UUID) async throws {
    guard let event = try await latestEventSnapshot(eventID: eventID) else { return }
    guard Date() >= event.revision.answersPublishedAt else { return }
    try await RatingSettlement.settle(
      eventID: eventID,
      organizerUserID: event.event.organizerUserID,
      answersPublishedAt: event.revision.answersPublishedAt,
      database: database
    )
  }

  func invalidateQuestionRating(questionID: UUID) async throws {
    try await RatingSettlement.invalidateQuestion(questionID: questionID, database: database)
  }

  func scoreEventParticipants(
    eventID: UUID
  ) async throws -> [(UUID, [(questionID: UUID, result: QuestionScoreResult)])] {
    let questions = try await latestEventQuestionSnapshots(eventID: eventID)
    var byUser: [UUID: [(questionID: UUID, result: QuestionScoreResult)]] = [:]
    for question in questions {
      let scores = try await scoreQuestion(eventID: eventID, questionID: question.question.id)
      for (scoredUserID, result) in scores {
        byUser[scoredUserID, default: []].append((question.question.id, result))
      }
    }
    return byUser.keys.sorted { $0.uuidString < $1.uuidString }.map { scoredUserID in
      (scoredUserID, byUser[scoredUserID] ?? [])
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
    guard !responses.isEmpty else { return [] }

    let responseIDs = responses.map(\.id)
    let allRevisions =
      try await EventQuestionResponseRevisionRecord
      .where { $0.eventQuestionResponseID.in(responseIDs) }
      .order { ($0.submittedAt.desc(), $0.id.desc()) }
      .fetchAll(db)
    var latestRevisionByResponseID: [UUID: EventQuestionResponseRevisionRecord] = [:]
    for revision in allRevisions {
      if latestRevisionByResponseID[revision.eventQuestionResponseID] == nil {
        latestRevisionByResponseID[revision.eventQuestionResponseID] = revision
      }
    }

    let revisionIDs = latestRevisionByResponseID.values.map(\.id)
    let allVarieties: [EventQuestionResponseVarietyRecord]
    if revisionIDs.isEmpty {
      allVarieties = []
    } else {
      allVarieties =
        try await EventQuestionResponseVarietyRecord
        .where { $0.eventQuestionResponseRevisionID.in(revisionIDs) }
        .fetchAll(db)
    }
    let varietiesByRevisionID = Dictionary(
      grouping: allVarieties, by: \.eventQuestionResponseRevisionID)

    var ancestorCache: [UUID: [RegionAncestor]] = [:]
    var results: [(UUID, QuestionScoreResult)] = []
    for response in responses {
      guard let revision = latestRevisionByResponseID[response.id] else { continue }
      let varieties = varietiesByRevisionID[revision.id, default: []].map(\.wineVarietyID)
      let responseAncestors: [RegionAncestor]
      if let regionID = revision.wineRegionID {
        if let cached = ancestorCache[regionID] {
          responseAncestors = cached
        } else {
          let loaded = try await regionAncestors(regionID: regionID, db: db)
          ancestorCache[regionID] = loaded
          responseAncestors = loaded
        }
      } else {
        responseAncestors = []
      }
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
