import Foundation
import Testing

@testable import App

@Suite
struct ScoringTests {
  @Test
  func alcoholExactAndPartialAndMiss() {
    let rule = EventQuestionScoreComponentRuleRecord(
      eventQuestionID: UUID(),
      component: .alcohol,
      points: 2,
      partialPoints: 1,
      alcoholTolerance: 0.5,
      createdAt: Date()
    )
    let correct = ScoringAnswerPayload(
      wineRegionID: nil,
      producerWineRegionID: nil,
      feature: nil,
      vintage: nil,
      alcoholByVolume: 13.0,
      wineVarietyIDs: []
    )

    let exact = QuestionScorer.score(
      correct: correct,
      response: ScoringAnswerPayload(
        wineRegionID: nil,
        producerWineRegionID: nil,
        feature: nil,
        vintage: nil,
        alcoholByVolume: 13.0,
        wineVarietyIDs: []
      ),
      regionRules: [],
      componentRules: [rule],
      correctRegionAncestors: [],
      responseRegionAncestors: []
    )
    #expect(exact.earnedPoints == 2)

    let partial = QuestionScorer.score(
      correct: correct,
      response: ScoringAnswerPayload(
        wineRegionID: nil,
        producerWineRegionID: nil,
        feature: nil,
        vintage: nil,
        alcoholByVolume: 13.4,
        wineVarietyIDs: []
      ),
      regionRules: [],
      componentRules: [rule],
      correctRegionAncestors: [],
      responseRegionAncestors: []
    )
    #expect(partial.earnedPoints == 1)

    let miss = QuestionScorer.score(
      correct: correct,
      response: ScoringAnswerPayload(
        wineRegionID: nil,
        producerWineRegionID: nil,
        feature: nil,
        vintage: nil,
        alcoholByVolume: 14.0,
        wineVarietyIDs: []
      ),
      regionRules: [],
      componentRules: [rule],
      correctRegionAncestors: [],
      responseRegionAncestors: []
    )
    #expect(miss.earnedPoints == 0)
  }

  @Test
  func regionAncestorPartialCreditUsesDeepestMatch() {
    let countryType = UUID()
    let communeType = UUID()
    let countryID = UUID()
    let communeID = UUID()
    let rules = [
      EventQuestionRegionScoreRuleRecord(
        eventQuestionID: UUID(),
        wineRegionTypeID: countryType,
        points: 1,
        createdAt: Date()
      ),
      EventQuestionRegionScoreRuleRecord(
        eventQuestionID: UUID(),
        wineRegionTypeID: communeType,
        points: 2,
        createdAt: Date()
      ),
    ]
    let correctAncestors = [
      RegionAncestor(id: communeID, wineRegionTypeID: communeType),
      RegionAncestor(id: countryID, wineRegionTypeID: countryType),
    ]
    let empty = ScoringAnswerPayload(
      wineRegionID: nil,
      producerWineRegionID: nil,
      feature: nil,
      vintage: nil,
      alcoholByVolume: nil,
      wineVarietyIDs: []
    )

    let full = QuestionScorer.score(
      correct: empty,
      response: empty,
      regionRules: rules,
      componentRules: [],
      correctRegionAncestors: correctAncestors,
      responseRegionAncestors: correctAncestors
    )
    #expect(full.earnedPoints == 2)
    #expect(full.maxPoints == 2)

    let partial = QuestionScorer.score(
      correct: empty,
      response: empty,
      regionRules: rules,
      componentRules: [],
      correctRegionAncestors: correctAncestors,
      responseRegionAncestors: [
        RegionAncestor(id: countryID, wineRegionTypeID: countryType)
      ]
    )
    #expect(partial.earnedPoints == 1)
  }

  @Test
  func varietyRequiresExactSetMatch() {
    let a = UUID()
    let b = UUID()
    let rule = EventQuestionScoreComponentRuleRecord(
      eventQuestionID: UUID(),
      component: .variety,
      points: 4,
      partialPoints: nil,
      alcoholTolerance: nil,
      createdAt: Date()
    )
    let correct = ScoringAnswerPayload(
      wineRegionID: nil,
      producerWineRegionID: nil,
      feature: nil,
      vintage: nil,
      alcoholByVolume: nil,
      wineVarietyIDs: [a, b]
    )
    let match = QuestionScorer.score(
      correct: correct,
      response: ScoringAnswerPayload(
        wineRegionID: nil,
        producerWineRegionID: nil,
        feature: nil,
        vintage: nil,
        alcoholByVolume: nil,
        wineVarietyIDs: [b, a]
      ),
      regionRules: [],
      componentRules: [rule],
      correctRegionAncestors: [],
      responseRegionAncestors: []
    )
    #expect(match.earnedPoints == 4)

    let miss = QuestionScorer.score(
      correct: correct,
      response: ScoringAnswerPayload(
        wineRegionID: nil,
        producerWineRegionID: nil,
        feature: nil,
        vintage: nil,
        alcoholByVolume: nil,
        wineVarietyIDs: [a]
      ),
      regionRules: [],
      componentRules: [rule],
      correctRegionAncestors: [],
      responseRegionAncestors: []
    )
    #expect(miss.earnedPoints == 0)
  }

  @Test
  func ratingDeltaGrowsWhenPerformanceIsRare() {
    #expect(RatingCalculator.delta(performance: 1, fieldAverage: 0) == 32)
    #expect(RatingCalculator.delta(performance: 1, fieldAverage: 1) == 0)
    #expect(RatingCalculator.delta(performance: 0, fieldAverage: 1) == -32)
    #expect(RatingCalculator.delta(performance: 1, fieldAverage: 0.5) == 16)
  }
}
