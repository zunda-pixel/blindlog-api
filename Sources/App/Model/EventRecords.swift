import Foundation
import Records
import StructuredQueriesPostgres

@Table("events")
struct EventRecord: Codable, Identifiable, Hashable {
  enum Visibility: String, Codable, QueryBindable, Sendable {
    case `public`
    case unlisted
    case `private`
  }

  var id: UUID
  @Column("organizer_user_id") var organizerUserID: UUID
  @Column("created_at") var createdAt: Date
}

@Table("event_revisions")
struct EventRevisionRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_id") var eventID: UUID
  var title: String
  var body: String
  @Column("image_id") var imageID: UUID?
  @Column("venue_name") var venueName: String
  @Column("venue_address_line1") var venueAddressLine1: String
  @Column("venue_address_line2") var venueAddressLine2: String?
  @Column("venue_locality") var venueLocality: String?
  @Column("venue_administrative_area") var venueAdministrativeArea: String?
  @Column("venue_postal_code") var venuePostalCode: String?
  @Column("venue_country_code") var venueCountryCode: String
  @Column("venue_latitude") var venueLatitude: Double?
  @Column("venue_longitude") var venueLongitude: Double?
  @Column("registration_starts_at") var registrationStartsAt: Date?
  @Column("registration_ends_at") var registrationEndsAt: Date?
  @Column("starts_at") var startsAt: Date
  @Column("ends_at") var endsAt: Date
  @Column("responses_due_at") var responsesDueAt: Date
  @Column("answers_published_at") var answersPublishedAt: Date
  var capacity: Int?
  @Column("entry_fee_minor_amount") var entryFeeMinorAmount: Int64?
  @Column("entry_fee_currency_code") var entryFeeCurrencyCode: String?
  var visibility: EventRecord.Visibility
  @Column("published_at") var publishedAt: Date?
  @Column("canceled_at") var canceledAt: Date?
  @Column("created_at") var createdAt: Date
}

@Table("event_participants")
struct EventParticipantRecord: Codable, Identifiable, Hashable {
  enum Status: String, Codable, QueryBindable, Sendable {
    case registered
    case waitlisted
    case canceled
    case attended
  }

  var id: UUID
  @Column("event_id") var eventID: UUID
  @Column("user_id") var userID: UUID
  var status: Status
  @Column("created_at") var createdAt: Date
}

@Table("event_questions")
struct EventQuestionRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_id") var eventID: UUID
  @Column("question_number") var questionNumber: Int
  @Column("created_at") var createdAt: Date
}

@Table("event_question_revisions")
struct EventQuestionRevisionRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_question_id") var eventQuestionID: UUID
  @Column("image_id") var imageID: UUID?
  var note: String?
  @Column("created_at") var createdAt: Date
}

@Table("event_question_region_score_rules")
struct EventQuestionRegionScoreRuleRecord: Codable, Hashable {
  @Column("event_question_id") var eventQuestionID: UUID
  @Column("wine_region_type_id") var wineRegionTypeID: UUID
  var points: Int
  @Column("created_at") var createdAt: Date
}

@Table("event_question_score_component_rules")
struct EventQuestionScoreComponentRuleRecord: Codable, Hashable {
  enum Component: String, Codable, QueryBindable, Sendable {
    case variety
    case vintage
    case alcohol
    case producer
    case feature
  }

  @Column("event_question_id") var eventQuestionID: UUID
  var component: Component
  var points: Int
  @Column("partial_points") var partialPoints: Int?
  @Column("alcohol_tolerance") var alcoholTolerance: Double?
  @Column("created_at") var createdAt: Date
}

@Table("wine_styles")
struct WineStyleRecord: Codable, Identifiable, Hashable {
  var id: UUID
  var code: String
  var name: String
  @Column("created_at") var createdAt: Date
}

@Table("wine_varieties")
struct WineVarietyRecord: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  @Column("created_at") var createdAt: Date
}

@Table("wine_variety_styles")
struct WineVarietyStyleRecord: Codable, Hashable {
  @Column("wine_variety_id") var wineVarietyID: UUID
  @Column("wine_style_id") var wineStyleID: UUID
  @Column("created_at") var createdAt: Date
}

@Table("wine_region_types")
struct WineRegionTypeRecord: Codable, Identifiable, Hashable {
  var id: UUID
  var code: String
  var name: String
  @Column("created_at") var createdAt: Date
}

@Table("wine_regions")
struct WineRegionRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("parent_region_id") var parentRegionID: UUID?
  @Column("wine_region_type_id") var wineRegionTypeID: UUID
  var name: String
  @Column("created_at") var createdAt: Date
}

@Table("event_question_correct_answers")
struct EventQuestionCorrectAnswerRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_question_id") var eventQuestionID: UUID
  @Column("created_at") var createdAt: Date
}

@Table("event_question_correct_answer_revisions")
struct EventQuestionCorrectAnswerRevisionRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_question_correct_answer_id") var eventQuestionCorrectAnswerID: UUID
  @Column("wine_region_id") var wineRegionID: UUID?
  @Column("producer_wine_region_id") var producerWineRegionID: UUID?
  var feature: String?
  var vintage: Int?
  @Column("alcohol_by_volume") var alcoholByVolume: Double?
  @Column("created_at") var createdAt: Date
}

@Table("event_question_correct_answer_revision_varieties")
struct EventQuestionCorrectAnswerVarietyRecord: Codable, Hashable {
  @Column("event_question_correct_answer_revision_id")
  var eventQuestionCorrectAnswerRevisionID: UUID
  @Column("wine_variety_id") var wineVarietyID: UUID
  @Column("created_at") var createdAt: Date
}

@Table("event_question_responses")
struct EventQuestionResponseRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_question_id") var eventQuestionID: UUID
  @Column("user_id") var userID: UUID
  @Column("created_at") var createdAt: Date
}

@Table("event_question_response_revisions")
struct EventQuestionResponseRevisionRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("event_question_response_id") var eventQuestionResponseID: UUID
  @Column("wine_region_id") var wineRegionID: UUID?
  @Column("producer_wine_region_id") var producerWineRegionID: UUID?
  var feature: String?
  var vintage: Int?
  @Column("alcohol_by_volume") var alcoholByVolume: Double?
  var note: String?
  @Column("submitted_at") var submittedAt: Date
}

@Table("event_question_response_revision_varieties")
struct EventQuestionResponseVarietyRecord: Codable, Hashable {
  @Column("event_question_response_revision_id") var eventQuestionResponseRevisionID: UUID
  @Column("wine_variety_id") var wineVarietyID: UUID
  @Column("created_at") var createdAt: Date
}

@Table("rating_seasons")
struct RatingSeasonRecord: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  @Column("starts_at") var startsAt: Date
  @Column("ends_at") var endsAt: Date?
  @Column("created_at") var createdAt: Date
}

@Table("user_season_ratings")
struct UserSeasonRatingRecord: Codable, Hashable {
  @Column("user_id") var userID: UUID
  @Column("season_id") var seasonID: UUID
  var rating: Int
  @Column("updated_at") var updatedAt: Date
}

@Table("user_rating_ledger")
struct UserRatingLedgerRecord: Codable, Identifiable, Hashable {
  var id: UUID
  @Column("user_id") var userID: UUID
  @Column("season_id") var seasonID: UUID
  @Column("event_question_id") var eventQuestionID: UUID
  var performance: Double
  @Column("field_average") var fieldAverage: Double
  var delta: Int
  @Column("rating_after") var ratingAfter: Int
  @Column("created_at") var createdAt: Date
}
