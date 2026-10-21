import FluentKit
import FluentSQL

// Agent connections, MCP, remote plans and the OAuth front door (OUT-001…OUT-004, AG-003).

/// OUT-001 / OUT-004 · tokens for MCP clients. The kind only picks the setup Settings shows;
/// scopes stay the same three.
struct AddAgentTokenKinds: SQLMigration {
    let forward = [
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other'))
        """,
    ]
    let backward = [
        "DELETE FROM agent_tokens WHERE kind <> 'stremio'",
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        "ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check CHECK (kind IN ('stremio'))",
    ]
}

/// AG-003 / OUT-004 · an outside agent's change that waits for the user. `op` is the exact
/// library write, worked out when the plan was made; `basis` is what the library looked like
/// then, so approval rejects a plan whose items moved. A denied or expired plan stays as the
/// record of what the token asked for.
struct CreateAgentPlans: SQLMigration {
    let forward = [
        """
        CREATE TABLE agent_plans (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            agent_token_id uuid REFERENCES agent_tokens(id) ON DELETE SET NULL,
            agent_name text NOT NULL,
            status text NOT NULL CHECK (status IN ('pending', 'applied', 'denied', 'stale', 'expired')),
            summary text NOT NULL,
            changes jsonb NOT NULL,
            counts jsonb NOT NULL,
            op jsonb NOT NULL,
            basis jsonb NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now(),
            expires_at timestamptz NOT NULL,
            decided_at timestamptz,
            action_id uuid REFERENCES actions(id) ON DELETE SET NULL
        )
        """,
        "CREATE INDEX agent_plans_user ON agent_plans (user_id, created_at DESC)",
        "CREATE INDEX agent_plans_pending_token ON agent_plans (agent_token_id) WHERE status = 'pending'",
    ]
    let backward = ["DROP TABLE agent_plans"]
}

/// OUT-004 · the OAuth front door for Claude's custom connector (MCP authorization spec):
/// clients register themselves (RFC 7591), the user approves in Aaru, and the access token is an
/// ordinary `agent_tokens` row (`issuance = oauth`, one hour) whose refresh token rotates.
/// Requests, codes and refresh tokens are kept only as hashes.
struct AddMCPOAuth: SQLMigration {
    let forward = [
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other', 'claude'))
        """,
        """
        ALTER TABLE agent_tokens
            ADD COLUMN issuance text NOT NULL DEFAULT 'secret' CHECK (issuance IN ('secret', 'oauth')),
            ADD COLUMN oauth_client_id text
        """,
        """
        CREATE TABLE oauth_clients (
            id text PRIMARY KEY,
            name text NOT NULL,
            redirect_uris text[] NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        """
        CREATE TABLE oauth_requests (
            id uuid PRIMARY KEY,
            client_id text NOT NULL REFERENCES oauth_clients(id) ON DELETE CASCADE,
            redirect_uri text NOT NULL,
            state text,
            code_challenge text NOT NULL,
            resource text,
            binding_hash text NOT NULL,
            expires_at timestamptz NOT NULL,
            consumed_at timestamptz
        )
        """,
        """
        CREATE TABLE oauth_codes (
            code_hash text PRIMARY KEY,
            client_id text NOT NULL REFERENCES oauth_clients(id) ON DELETE CASCADE,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            redirect_uri text NOT NULL,
            code_challenge text NOT NULL,
            resource text,
            name text NOT NULL,
            kind text NOT NULL,
            allow_writes boolean NOT NULL,
            expires_at timestamptz NOT NULL,
            consumed_at timestamptz,
            agent_token_id uuid REFERENCES agent_tokens(id) ON DELETE SET NULL
        )
        """,
        """
        CREATE TABLE oauth_refresh_tokens (
            token_hash text PRIMARY KEY,
            agent_token_id uuid NOT NULL REFERENCES agent_tokens(id) ON DELETE CASCADE,
            client_id text NOT NULL,
            expires_at timestamptz NOT NULL,
            consumed_at timestamptz
        )
        """,
        "CREATE INDEX oauth_refresh_tokens_token ON oauth_refresh_tokens (agent_token_id)",
    ]
    let backward = [
        "DROP TABLE oauth_refresh_tokens",
        "DROP TABLE oauth_codes",
        "DROP TABLE oauth_requests",
        "DROP TABLE oauth_clients",
        "DELETE FROM agent_tokens WHERE kind = 'claude'",
        "ALTER TABLE agent_tokens DROP COLUMN oauth_client_id, DROP COLUMN issuance",
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other'))
        """,
    ]
}

/// AG-001 `plan_import` · an MCP token may queue an import when the user allowed it. The import
/// still waits for the user's approval like any other; the scope never applies anything.
struct AddImportsWriteScope: SQLMigration {
    let forward = [
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_scopes_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_scopes_check
            CHECK (scopes <@ ARRAY['library:read', 'library:write', 'scrobble:write', 'imports:write']::text[])
        """,
    ]
    let backward = [
        "UPDATE agent_tokens SET scopes = array_remove(scopes, 'imports:write')",
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_scopes_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_scopes_check
            CHECK (scopes <@ ARRAY['library:read', 'library:write', 'scrobble:write']::text[])
        """,
    ]
}

/// SCR-007 · the browser extension's tokens (`browser`, scrobble only) and the streaming sites its
/// watch events come from.
struct AddBrowserScrobbler: SQLMigration {
    let forward = [
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other', 'claude', 'browser'))
        """,
        "ALTER TABLE watch_events DROP CONSTRAINT watch_events_source_check",
        """
        ALTER TABLE watch_events ADD CONSTRAINT watch_events_source_check
            CHECK (source IN ('stremio', 'netflix', 'disney_plus', 'prime_video'))
        """,
    ]
    let backward = [
        "DELETE FROM watch_events WHERE source <> 'stremio'",
        "ALTER TABLE watch_events DROP CONSTRAINT watch_events_source_check",
        "ALTER TABLE watch_events ADD CONSTRAINT watch_events_source_check CHECK (source IN ('stremio'))",
        "DELETE FROM agent_tokens WHERE kind = 'browser'",
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other', 'claude'))
        """,
    ]
}
