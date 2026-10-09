import FluentKit
import FluentSQL

// Schema migrations, in order. Raw SQL because the rules that matter here — partial
// unique indexes, CHECK constraints — are not expressible in Fluent's schema builder.
// Never edit a migration that has shipped; add a new one.

/// All migrations, in apply order.
let allMigrations: [any Migration] = [
    CreateUsers(),
    CreateTitles(),
    CreateLibrary(),
    CreateImportJobs(),
]

struct MigrationNeedsSQL: Error, CustomStringConvertible {
    var description: String {
        "Aaru migrations need a SQL database (Postgres)."
    }
}

/// A migration expressed as SQL statements, applied in order and reverted in reverse.
protocol SQLMigration: AsyncMigration {
    var forward: [String] { get }
    var backward: [String] { get }
}

extension SQLMigration {
    func prepare(on database: any Database) async throws {
        try await run(forward, on: database)
    }

    func revert(on database: any Database) async throws {
        try await run(backward, on: database)
    }

    private func run(_ statements: [String], on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { throw MigrationNeedsSQL() }
        for statement in statements {
            try await sql.raw(SQLQueryString(statement)).run()
        }
    }
}

/// SRV-004 · users and auth identities.
struct CreateUsers: SQLMigration {
    let forward = [
        """
        CREATE TABLE users (
            id uuid PRIMARY KEY,
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        """
        CREATE TABLE auth_identities (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            provider text NOT NULL CHECK (provider IN ('apple', 'email')),
            provider_subject text NOT NULL,
            email text,
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (provider, provider_subject)
        )
        """,
        "CREATE INDEX auth_identities_user_id ON auth_identities (user_id)",
    ]
    let backward = ["DROP TABLE auth_identities", "DROP TABLE users"]
}

/// SRV-005 · titles and episodes.
///
/// TMDB and Trakt number movies and shows separately, so their ids are unique per
/// `type`. Every other id is globally unique. Anime ids (`anilist`, `mal`, `anidb`)
/// are created here because SRV-005 had not shipped when CAT-008 was planned.
struct CreateTitles: SQLMigration {
    static let typeScopedIDs = ["tmdb", "trakt"]
    static let globalIDs = ["imdb", "tvdb", "isbn", "open_library", "anilist", "mal", "anidb"]

    var forward: [String] {
        let table = """
        CREATE TABLE titles (
            id uuid PRIMARY KEY,
            type text NOT NULL CHECK (type IN ('movie', 'show', 'book')),
            title text NOT NULL CHECK (btrim(title) <> ''),
            original_title text,
            year integer CHECK (year BETWEEN 1870 AND 2200),
            synopsis text,
            poster_url text,
            tmdb text,
            imdb text,
            trakt text,
            tvdb text,
            isbn text,
            open_library text,
            anilist text,
            mal text,
            anidb text,
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """
        let scoped = Self.typeScopedIDs.map {
            "CREATE UNIQUE INDEX titles_type_\($0)_key ON titles (type, \($0)) WHERE \($0) IS NOT NULL"
        }
        let global = Self.globalIDs.map {
            "CREATE UNIQUE INDEX titles_\($0)_key ON titles (\($0)) WHERE \($0) IS NOT NULL"
        }
        let episodes = """
        CREATE TABLE show_episodes (
            id uuid PRIMARY KEY,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
            season integer NOT NULL CHECK (season >= 0),
            episode integer NOT NULL CHECK (episode >= 1),
            name text,
            airs_at timestamptz,
            tmdb_episode_id text,
            UNIQUE (title_id, season, episode)
        )
        """
        return [table] + scoped + global + [episodes]
    }

    let backward = ["DROP TABLE show_episodes", "DROP TABLE titles"]
}

/// SRV-006 · library items, episode progress, lists.
struct CreateLibrary: SQLMigration {
    let forward = [
        """
        CREATE TABLE library_items (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE RESTRICT,
            status text NOT NULL CHECK (status IN ('wishlist', 'in_progress', 'finished', 'dropped')),
            is_owned boolean NOT NULL DEFAULT false,
            rating double precision CHECK (rating BETWEEN 1 AND 10 AND rating * 2 = floor(rating * 2)),
            notes text,
            added_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL,
            finished_at timestamptz,
            UNIQUE (user_id, title_id)
        )
        """,
        "CREATE INDEX library_items_user_updated ON library_items (user_id, updated_at, id)",
        """
        CREATE TABLE episode_progress (
            id uuid PRIMARY KEY,
            library_item_id uuid NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,
            season integer NOT NULL CHECK (season >= 0),
            episode integer NOT NULL CHECK (episode >= 1),
            watched_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (library_item_id, season, episode)
        )
        """,
        """
        CREATE TABLE lists (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name text NOT NULL CHECK (btrim(name) <> ''),
            visibility text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private')),
            created_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL
        )
        """,
        "CREATE INDEX lists_user_id ON lists (user_id)",
        """
        CREATE TABLE list_items (
            id uuid PRIMARY KEY,
            list_id uuid NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE RESTRICT,
            position integer NOT NULL,
            added_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (list_id, title_id)
        )
        """,
    ]
    let backward = [
        "DROP TABLE list_items",
        "DROP TABLE lists",
        "DROP TABLE episode_progress",
        "DROP TABLE library_items",
    ]
}

/// SRV-007 · import jobs.
struct CreateImportJobs: SQLMigration {
    let forward = [
        """
        CREATE TABLE import_jobs (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            source text NOT NULL,
            state text NOT NULL CHECK (state IN ('queued', 'running', 'succeeded', 'failed', 'partial')),
            stats jsonb NOT NULL,
            error_summary text,
            created_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL
        )
        """,
        "CREATE INDEX import_jobs_user_created ON import_jobs (user_id, created_at DESC)",
    ]
    let backward = ["DROP TABLE import_jobs"]
}
