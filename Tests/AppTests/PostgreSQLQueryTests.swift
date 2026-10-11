import Foundation
import ISO_9075_Foundation
import PostgreSQL
import PostgresNIO
import SQL
import SQL_Foundation_Integration
import Testing

struct PostgreSQLQueryTests {
  @Test
  func foundationValuesUsePostgresBindings() throws {
    let id = UUID()
    let date = Date(timeIntervalSince1970: 1_700_000_000.125)
    let data = Data([0, 127, 128, 255])
    let fragment: ISO_9075.Fragment =
      "SELECT \(id, as: UUID.self), \(date, as: Date.self), \(data, as: Data.self)"
    let rendering = PostgreSQL().render(fragment)
    #expect(rendering.sql == "SELECT $1, $2, $3")
    #expect(rendering.values == [id.queryBinding, date.queryBinding, data.queryBinding])
    let query = try PostgresQuery(rendering)
    #expect(query.binds.count == 3)
  }

  @Test
  func untrustedTextRemainsABoundParameter() throws {
    let input = "x'; DROP TABLE users; --"
    let fragment: ISO_9075.Fragment = "SELECT \(input, as: String.self)"
    let rendering = PostgreSQL().render(fragment)
    #expect(rendering.sql == "SELECT $1")
    #expect(rendering.values == [.text(input)])
    let query = try PostgresQuery(rendering)
    #expect(query.binds.count == 1)
  }
}
