import Foundation
import HummingbirdTesting
import NIOCore
import Testing

@testable import App

@Suite(.serialized)
struct EventScoringRouterTests {
  @Test
  func eventScoresExcludeOrganizerAndSettleRatings() async throws {
    let arguments = TestArguments()
    let app = try await buildApplication(arguments)
    let ipAddress = UUID().uuidString
    let now = Date().timeIntervalSinceReferenceDate
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    try await app.test(.router) { client in
      func createUser() async throws -> Components.Schemas.UserToken {
        try await client.execute(
          uri: "/user",
          method: .post,
          headers: [.cfConnectingIP: ipAddress]
        ) { response in
          #expect(response.status == .ok)
          return try decoder.decode(Components.Schemas.UserToken.self, from: response.body)
        }
      }

      func eventRequest(
        startsAt: Double,
        responsesDueAt: Double,
        answersPublishedAt: Double
      ) -> Components.Schemas.CreateEventRequest {
        .init(
          title: "Scoring integration",
          body: "Score and rating flow",
          venueName: "Blind Tasting Room",
          venueAddress: .init(addressLine1: "1 Wine Street", countryCode: "JP"),
          eventPeriod: .init(startsAt: startsAt, endsAt: startsAt + 3600),
          responsesDueAt: responsesDueAt,
          answersPublishedAt: answersPublishedAt,
          visibility: ._public,
          publishedAt: startsAt - 100
        )
      }

      let organizer = try await createUser()
      let highScorer = try await createUser()
      let lowScorer = try await createUser()

      guard let organizerID = UUID(uuidString: organizer.userID) else {
        Issue.record("organizer userID is not a UUID")
        return
      }
      AdminUserIDs.testOverride.withLock { $0 = [organizerID] }
      defer { AdminUserIDs.testOverride.withLock { $0 = nil } }

      let seasonResponse = try await client.execute(
        uri: "/ratings/seasons",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ],
        body: ByteBuffer(
          data: try encoder.encode(
            Components.Schemas.CreateRatingSeasonRequest(name: "Season \(UUID())")
          )
        )
      )
      #expect(seasonResponse.status == .ok)

      let event = try await client.execute(
        uri: "/events",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ],
        body: ByteBuffer(
          data: try encoder.encode(
            eventRequest(
              startsAt: now - 100,
              responsesDueAt: now + 3600,
              answersPublishedAt: now + 7200
            )
          )
        )
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.Event.self, from: response.body)
      }

      for participant in [highScorer, lowScorer] {
        let join = try await client.execute(
          uri: "/events/\(event.id)/participants",
          method: .post,
          headers: [
            .cfConnectingIP: ipAddress,
            .authorization: "Bearer \(participant.token)",
          ]
        )
        #expect(join.status == .ok)
      }

      let question = try await client.execute(
        uri: "/events/\(event.id)/questions",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ],
        body: ByteBuffer(
          data: try encoder.encode(
            Components.Schemas.CreateEventQuestionRequest(
              questionNumber: 1,
              scoreComponentRules: [
                .init(component: .vintage, points: 10)
              ]
            )
          )
        )
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.EventQuestion.self, from: response.body)
      }

      let createAnswer = try await client.execute(
        uri: "/events/\(event.id)/questions/\(question.id)/correct_answer",
        method: .post,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ],
        body: ByteBuffer(
          data: try encoder.encode(
            Components.Schemas.CreateEventQuestionCorrectAnswerRequest(
              vintage: 2015,
              wineVarietyIDs: []
            )
          )
        )
      )
      #expect(createAnswer.status == .ok)

      func submitResponse(token: String, vintage: Int32) async throws {
        let response = try await client.execute(
          uri: "/events/\(event.id)/questions/\(question.id)/responses",
          method: .post,
          headers: [
            .cfConnectingIP: ipAddress,
            .authorization: "Bearer \(token)",
          ],
          body: ByteBuffer(
            data: try encoder.encode(
              Components.Schemas.CreateEventQuestionResponseRequest(
                vintage: vintage,
                wineVarietyIDs: []
              )
            )
          )
        )
        #expect(response.status == .ok)
      }

      try await submitResponse(token: organizer.token, vintage: 2015)
      try await submitResponse(token: highScorer.token, vintage: 2015)
      try await submitResponse(token: lowScorer.token, vintage: 2010)

      let forbiddenBeforePublish = try await client.execute(
        uri: "/events/\(event.id)/leaderboard",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(highScorer.token)",
        ]
      )
      #expect(forbiddenBeforePublish.status == .forbidden)

      let publishedAt = Date().timeIntervalSinceReferenceDate
      let publishUpdate = try await client.execute(
        uri: "/events/\(event.id)",
        method: .put,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ],
        body: ByteBuffer(
          data: try encoder.encode(
            eventRequest(
              startsAt: now - 100,
              responsesDueAt: publishedAt - 1,
              answersPublishedAt: publishedAt
            )
          )
        )
      )
      #expect(publishUpdate.status == .ok)

      let leaderboard = try await client.execute(
        uri: "/events/\(event.id)/leaderboard",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(highScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(
          [Components.Schemas.EventLeaderboardEntry].self,
          from: response.body
        )
      }
      #expect(leaderboard.map(\.userID) == [highScorer.userID, lowScorer.userID])
      #expect(Set(leaderboard.map(\.userID)).contains(organizer.userID) == false)
      #expect(leaderboard[0].rank == 1)
      #expect(leaderboard[0].totalEarnedPoints == 10)
      #expect(leaderboard[1].rank == 2)
      #expect(leaderboard[1].totalEarnedPoints == 0)

      let eventScores = try await client.execute(
        uri: "/events/\(event.id)/scores",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(
          [Components.Schemas.EventParticipantScore].self,
          from: response.body
        )
      }
      #expect(Set(eventScores.map(\.userID)) == Set([highScorer.userID, lowScorer.userID]))

      let questionScores = try await client.execute(
        uri: "/events/\(event.id)/questions/\(question.id)/scores",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(highScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(
          [Components.Schemas.EventQuestionUserScore].self,
          from: response.body
        )
      }
      #expect(Set(questionScores.map(\.userID)) == Set([highScorer.userID, lowScorer.userID]))

      let highRating = try await client.execute(
        uri: "/me/rating",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(highScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.UserRating.self, from: response.body)
      }
      #expect(highRating.rating == Int32(RatingSettlement.initialRating + 16))
      #expect(highRating.recentLedger.count == 1)

      let lowRating = try await client.execute(
        uri: "/me/rating",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(lowScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.UserRating.self, from: response.body)
      }
      #expect(lowRating.rating == Int32(RatingSettlement.initialRating - 16))

      let organizerRating = try await client.execute(
        uri: "/me/rating",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.UserRating.self, from: response.body)
      }
      #expect(organizerRating.rating == Int32(RatingSettlement.initialRating))
      #expect(organizerRating.recentLedger.isEmpty)

      let updateAnswer = try await client.execute(
        uri: "/events/\(event.id)/questions/\(question.id)/correct_answer",
        method: .put,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(organizer.token)",
        ],
        body: ByteBuffer(
          data: try encoder.encode(
            Components.Schemas.CreateEventQuestionCorrectAnswerRequest(
              vintage: 2010,
              wineVarietyIDs: []
            )
          )
        )
      )
      #expect(updateAnswer.status == .ok)

      let leaderboardAfterUpdate = try await client.execute(
        uri: "/events/\(event.id)/leaderboard",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(highScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(
          [Components.Schemas.EventLeaderboardEntry].self,
          from: response.body
        )
      }
      #expect(leaderboardAfterUpdate.map(\.userID) == [lowScorer.userID, highScorer.userID])
      #expect(leaderboardAfterUpdate[0].totalEarnedPoints == 10)
      #expect(leaderboardAfterUpdate[1].totalEarnedPoints == 0)

      let highRatingAfterUpdate = try await client.execute(
        uri: "/me/rating",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(highScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.UserRating.self, from: response.body)
      }
      #expect(highRatingAfterUpdate.rating == Int32(RatingSettlement.initialRating - 16))

      let lowRatingAfterUpdate = try await client.execute(
        uri: "/me/rating",
        method: .get,
        headers: [
          .cfConnectingIP: ipAddress,
          .authorization: "Bearer \(lowScorer.token)",
        ]
      ) { response in
        #expect(response.status == .ok)
        return try decoder.decode(Components.Schemas.UserRating.self, from: response.body)
      }
      #expect(lowRatingAfterUpdate.rating == Int32(RatingSettlement.initialRating + 16))
    }
  }
}
