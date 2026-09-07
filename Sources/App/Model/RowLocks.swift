import Foundation
import PostgresNIO
import Records
import StructuredQueriesPostgres

/// Row-level locks used inside transactions. The ORM does not yet expose `FOR UPDATE`.
enum RowLocks {
  static func event(
    _ eventID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws {
    let query: QueryFragment =
      "SELECT id FROM public.events WHERE id = \(eventID, as: UUID.self) FOR UPDATE"
    try await db.executeFragment(query)
  }

  static func eventQuestion(
    _ questionID: UUID,
    db: any Database.Connection.`Protocol`
  ) async throws {
    let query: QueryFragment =
      "SELECT id FROM public.event_questions WHERE id = \(questionID, as: UUID.self) FOR UPDATE"
    try await db.executeFragment(query)
  }
}
