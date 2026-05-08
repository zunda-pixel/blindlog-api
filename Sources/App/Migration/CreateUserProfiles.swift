import Logging
import PostgresMigrations
import PostgresNIO

struct CreateUserProfiles: DatabaseMigration {
  func apply(connection: PostgresConnection, logger: Logger) async throws {
    try await connection.query(
      """
      CREATE TABLE IF NOT EXISTS public.user_profiles (
        id uuid NOT NULL,
        user_id uuid NOT NULL,
        name text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT user_profiles_pk PRIMARY KEY (id),
        CONSTRAINT user_profiles_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE,
        CONSTRAINT user_profiles_name_length CHECK (char_length(trim(name)) BETWEEN 1 AND 100)
      )
      """,
      logger: logger
    )

    try await connection.query(
      """
      CREATE INDEX IF NOT EXISTS user_profiles_latest_idx
        ON public.user_profiles(user_id, created_at DESC, id DESC)
      """,
      logger: logger
    )
  }

  func revert(connection: PostgresConnection, logger: Logger) async throws {
    try await connection.query(
      "DROP INDEX IF EXISTS public.user_profiles_latest_idx",
      logger: logger
    )
    try await connection.query(
      "DROP TABLE IF EXISTS public.user_profiles",
      logger: logger
    )
  }
}
