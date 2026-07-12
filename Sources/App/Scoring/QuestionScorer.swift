import Foundation

enum ScoreComponentKind: String, Sendable, Hashable {
  case region
  case variety
  case vintage
  case alcohol
  case producer
  case feature
}

struct ScoreComponentResult: Sendable, Hashable {
  var component: ScoreComponentKind
  var earnedPoints: Int
  var maxPoints: Int
}

struct QuestionScoreResult: Sendable, Hashable {
  var components: [ScoreComponentResult]
  var earnedPoints: Int
  var maxPoints: Int

  var performance: Double {
    guard maxPoints > 0 else { return 0 }
    return Double(earnedPoints) / Double(maxPoints)
  }
}

struct ScoringAnswerPayload: Sendable, Hashable {
  var wineRegionID: UUID?
  var producerWineRegionID: UUID?
  var feature: String?
  var vintage: Int?
  var alcoholByVolume: Double?
  var wineVarietyIDs: Set<UUID>
}

struct RegionAncestor: Sendable, Hashable {
  var id: UUID
  var wineRegionTypeID: UUID
}

enum QuestionScorer {
  static let alcoholExactEpsilon = 1e-9

  static func normalizeFeature(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
  }

  static func score(
    correct: ScoringAnswerPayload,
    response: ScoringAnswerPayload,
    regionRules: [EventQuestionRegionScoreRuleRecord],
    componentRules: [EventQuestionScoreComponentRuleRecord],
    correctRegionAncestors: [RegionAncestor],
    responseRegionAncestors: [RegionAncestor]
  ) -> QuestionScoreResult {
    var components: [ScoreComponentResult] = []
    let hasFeatureRule = componentRules.contains { $0.component == .feature }

    if !regionRules.isEmpty {
      let maxPoints = regionRules.map(\.points).max() ?? 0
      let pointsByType = Dictionary(
        regionRules.map { ($0.wineRegionTypeID, $0.points) },
        uniquingKeysWith: { current, _ in current }
      )
      let responseIDs = Set(responseRegionAncestors.map(\.id))
      var earned = 0
      for ancestor in correctRegionAncestors where responseIDs.contains(ancestor.id) {
        if let points = pointsByType[ancestor.wineRegionTypeID] {
          earned = max(earned, points)
        }
      }
      components.append(
        ScoreComponentResult(component: .region, earnedPoints: earned, maxPoints: maxPoints)
      )
    }

    for rule in componentRules {
      let result: ScoreComponentResult
      switch rule.component {
      case .variety:
        let earned =
          !correct.wineVarietyIDs.isEmpty
            && correct.wineVarietyIDs == response.wineVarietyIDs ? rule.points : 0
        result = ScoreComponentResult(
          component: .variety,
          earnedPoints: earned,
          maxPoints: rule.points
        )
      case .vintage:
        let earned =
          correct.vintage != nil && correct.vintage == response.vintage ? rule.points : 0
        result = ScoreComponentResult(
          component: .vintage,
          earnedPoints: earned,
          maxPoints: rule.points
        )
      case .alcohol:
        let earned = alcoholPoints(
          correct: correct.alcoholByVolume,
          response: response.alcoholByVolume,
          points: rule.points,
          partialPoints: rule.partialPoints,
          tolerance: rule.alcoholTolerance
        )
        result = ScoreComponentResult(
          component: .alcohol,
          earnedPoints: earned,
          maxPoints: rule.points
        )
      case .producer:
        let earned = producerPoints(
          correct: correct,
          response: response,
          points: rule.points,
          partialPoints: rule.partialPoints,
          allowFeaturePartial: !hasFeatureRule
        )
        result = ScoreComponentResult(
          component: .producer,
          earnedPoints: earned,
          maxPoints: rule.points
        )
      case .feature:
        let correctFeature = normalizeFeature(correct.feature)
        let responseFeature = normalizeFeature(response.feature)
        let earned =
          correctFeature != nil && correctFeature == responseFeature ? rule.points : 0
        result = ScoreComponentResult(
          component: .feature,
          earnedPoints: earned,
          maxPoints: rule.points
        )
      }
      components.append(result)
    }

    let earnedPoints = components.reduce(0) { $0 + $1.earnedPoints }
    let maxPoints = components.reduce(0) { $0 + $1.maxPoints }
    return QuestionScoreResult(
      components: components,
      earnedPoints: earnedPoints,
      maxPoints: maxPoints
    )
  }

  private static func alcoholPoints(
    correct: Double?,
    response: Double?,
    points: Int,
    partialPoints: Int?,
    tolerance: Double?
  ) -> Int {
    guard let correct, let response else { return 0 }
    let delta = abs(correct - response)
    if delta <= alcoholExactEpsilon { return points }
    if let tolerance, delta <= tolerance {
      return partialPoints ?? 0
    }
    return 0
  }

  /// Full points for matching producer IDs.
  /// Partial points when the correct producer is known and the response is blank (anonymous),
  /// or — only when there is no separate feature rule — when features match.
  private static func producerPoints(
    correct: ScoringAnswerPayload,
    response: ScoringAnswerPayload,
    points: Int,
    partialPoints: Int?,
    allowFeaturePartial: Bool
  ) -> Int {
    guard let correctProducer = correct.producerWineRegionID else { return 0 }
    if response.producerWineRegionID == correctProducer {
      return points
    }
    guard let partialPoints else { return 0 }
    if response.producerWineRegionID == nil {
      return partialPoints
    }
    if allowFeaturePartial {
      let correctFeature = normalizeFeature(correct.feature)
      let responseFeature = normalizeFeature(response.feature)
      if correctFeature != nil, correctFeature == responseFeature {
        return partialPoints
      }
    }
    return 0
  }
}

enum RatingCalculator {
  static let kFactor = 32
  static let maxAbsDelta = 50

  static func delta(performance: Double, fieldAverage: Double) -> Int {
    let raw = Double(kFactor) * (performance - fieldAverage)
    let rounded = Int(raw.rounded())
    return min(maxAbsDelta, max(-maxAbsDelta, rounded))
  }
}

enum Ranking {
  /// Competition ranking: equal scores share the same rank (1, 2, 2, 4).
  static func competitionRanks<T>(
    _ rows: [T],
    score: (T) -> Int
  ) -> [(rank: Int32, row: T)] {
    guard !rows.isEmpty else { return [] }
    var result: [(rank: Int32, row: T)] = []
    var index = 0
    var currentRank: Int32 = 1
    var previousScore: Int?
    for row in rows {
      let value = score(row)
      if let previousScore, value != previousScore {
        currentRank = Int32(index + 1)
      } else if previousScore == nil {
        currentRank = 1
      }
      result.append((currentRank, row))
      previousScore = value
      index += 1
    }
    return result
  }
}
