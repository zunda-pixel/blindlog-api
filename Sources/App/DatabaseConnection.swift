import ISO_9075_Foundation
import Logging
import PostgreSQL
import PostgresNIO
import SQL

/// Executes the PostgreSQL DSL through PostgresNIO without blocking an event loop.
struct DatabaseConnection: Sendable {
  let postgres: PostgresConnection
  let logger: Logger

  func executeFragment(_ fragment: ISO_9075.Fragment) async throws {
    let query = try PostgresQuery(PostgreSQL().render(fragment))
    for try await _ in try await postgres.query(query, logger: logger) {}
  }

  func fetch<Value>(
    _ fragment: ISO_9075.Fragment,
    decode: (inout PostgreSQL.Decoder) throws -> Value
  ) async throws -> [Value] {
    let query = try PostgresQuery(PostgreSQL().render(fragment))
    let rows = try await postgres.query(query, logger: logger)
    var result: [Value] = []
    for try await row in rows {
      var decoder = PostgreSQL.Decoder(row: PostgreSQL.Row(row))
      result.append(try decode(&decoder))
    }
    return result
  }
}

extension PostgresClient {
  func read<Value: Sendable>(
    _ body: @Sendable (DatabaseConnection) async throws -> Value
  ) async throws -> Value {
    try await withConnection { connection in
      try await body(
        DatabaseConnection(postgres: connection, logger: Logger(label: "App.Database")))
    }
  }

  func write<Value: Sendable>(
    _ body: @Sendable (DatabaseConnection) async throws -> Value
  ) async throws -> Value {
    try await read(body)
  }

  func withTransaction<Value: Sendable>(
    _ body: @Sendable (DatabaseConnection) async throws -> Value
  ) async throws -> Value {
    let logger = Logger(label: "App.Database")
    do {
      return try await withTransaction(logger: logger) { connection in
        try await body(DatabaseConnection(postgres: connection, logger: logger))
      }
    } catch let error as PostgresTransactionError {
      // Preserve domain errors thrown by the API after a successful rollback.
      if let failure = error.closureError, error.rollbackError == nil {
        throw failure
      }
      throw error
    }
  }
}

extension Statement {
  func execute(_ db: DatabaseConnection) async throws where QueryValue == () {
    try await db.executeFragment(query)
  }

  func fetchAll(_ db: DatabaseConnection) async throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    try await db.fetch(query) { decoder in try QueryValue(decoder: &decoder).queryOutput }
  }

  func fetchOne(_ db: DatabaseConnection) async throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    try await fetchAll(db).first
  }

  func fetchAll<each Value: QueryRepresentable>(
    _ db: DatabaseConnection
  ) async throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    try await db.fetch(query) { decoder in try decoder.decodeColumns((repeat each Value).self) }
  }
}

extension Table {
  static func fetchAll(_ db: DatabaseConnection) async throws -> [QueryOutput] {
    try await all.fetchAll(db)
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  func fetchCount(_ db: DatabaseConnection) async throws -> Int {
    try await asSelect().count().fetchOne(db) ?? 0
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  func fetchAll(_ db: DatabaseConnection) async throws -> [From.QueryOutput] {
    try await db.fetch(query) { decoder in try From(decoder: &decoder).queryOutput }
  }

  func fetchOne(_ db: DatabaseConnection) async throws -> From.QueryOutput? {
    try await asSelect().limit(1).fetchAll(db).first
  }
}

extension SelectStatement where QueryValue == () {
  func fetchAll<each Join: Table>(
    _ db: DatabaseConnection
  ) async throws -> [(From.QueryOutput, repeat (each Join).QueryOutput)]
  where Joins == (repeat each Join) {
    try await db.fetch(query) { decoder in
      try decoder.decodeColumns((From, repeat each Join).self)
    }
  }
}
