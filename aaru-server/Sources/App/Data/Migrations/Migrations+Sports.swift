/// SPT-001 · the Sports tab: the leagues, teams and players a user follows, by the provider's id
/// with a snapshot of the name, sport and badge, and the one country "Where to watch" looks at.
/// Sports-only: nothing else reads these tables.
struct CreateSports: SQLMigration {
    let forward = [
        """
        CREATE TABLE sport_follows (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            kind text NOT NULL CHECK (kind IN ('league', 'team', 'player')),
            provider_id text NOT NULL CHECK (char_length(provider_id) BETWEEN 1 AND 40),
            name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 300),
            sport text NOT NULL CHECK (char_length(sport) <= 100),
            badge_url text CHECK (char_length(badge_url) <= 1000),
            country text CHECK (char_length(country) <= 200),
            league_id text CHECK (char_length(league_id) <= 40),
            team_id text CHECK (char_length(team_id) <= 40),
            team_name text CHECK (char_length(team_name) <= 300),
            created_at timestamptz NOT NULL,
            PRIMARY KEY (user_id, kind, provider_id)
        )
        """,
        """
        CREATE TABLE sport_settings (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            watch_country_code text CHECK (char_length(watch_country_code) = 2),
            updated_at timestamptz NOT NULL
        )
        """,
    ]
    let backward = [
        "DROP TABLE sport_settings",
        "DROP TABLE sport_follows",
    ]
}
