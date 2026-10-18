import Foundation
import ISO_9075_Call_Level_Interface
import ISO_9075_Foundation
import PostgreSQL
import SQL
import SQL_Foundation_Integration

/// Row-level locks used inside transactions. The ORM does not yet expose `FOR UPDATE`.
enum RowLocks {
  static func event(
    _ eventID: UUID,
    db: PostgreSQL.Connection
  ) throws(ISO_9075.Error) {
    let query: ISO_9075.Fragment =
      "SELECT id FROM public.events WHERE id = \(eventID, as: UUID.self) FOR UPDATE"
    _ = try db.execute(query)
  }

  static func eventQuestion(
    _ questionID: UUID,
    db: PostgreSQL.Connection
  ) throws(ISO_9075.Error) {
    let query: ISO_9075.Fragment =
      "SELECT id FROM public.event_questions WHERE id = \(questionID, as: UUID.self) FOR UPDATE"
    _ = try db.execute(query)
  }

  static func userSeasonRating(
    userID: UUID,
    seasonID: UUID,
    db: PostgreSQL.Connection
  ) throws(ISO_9075.Error) {
    let query: ISO_9075.Fragment = """
      SELECT user_id FROM public.user_season_ratings
      WHERE user_id = \(userID, as: UUID.self) AND season_id = \(seasonID, as: UUID.self)
      FOR UPDATE
      """
    _ = try db.execute(query)
  }
}
