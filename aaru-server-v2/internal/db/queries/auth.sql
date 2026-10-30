-- name: SessionUserID :one
SELECT user_id FROM sessions WHERE token_hash = $1 AND expires_at > $2;

-- name: CountUsers :one
SELECT count(*) FROM users;

-- Users and identities (AUTH-002…005).

-- name: CreateUser :exec
INSERT INTO users (id, first_name, last_name, display_name)
VALUES (@id, sqlc.narg('first_name'), sqlc.narg('last_name'), sqlc.narg('display_name'));

-- name: CreateAuthIdentity :exec
INSERT INTO auth_identities (id, user_id, provider, provider_subject, email)
VALUES (@id, @user_id, @provider, @provider_subject, sqlc.narg('email'));

-- A new account has no history to backfill: its first badge is a live unlock.
-- name: CreateUserProgress :exec
INSERT INTO user_progress (user_id, evaluated_at) VALUES (@user_id, now());

-- name: UserForIdentity :one
SELECT user_id FROM auth_identities WHERE provider = @provider AND provider_subject = @provider_subject LIMIT 1;

-- name: UserProfile :one
SELECT u.first_name, u.last_name, p.handle, u.avatar_version
FROM users u LEFT JOIN profiles p ON p.user_id = u.id
WHERE u.id = @id;

-- name: UserIdentities :many
SELECT provider, email FROM auth_identities WHERE user_id = @user_id ORDER BY provider;

-- Account deletion (AUTH-004). Magic links are keyed by email, not user, so they do not cascade.
-- name: DeleteUserMagicLinks :exec
DELETE FROM magic_links WHERE email IN (
    SELECT email FROM auth_identities WHERE user_id = @user_id AND email IS NOT NULL
);

-- Group messages are server-visible, so an account's messages are emptied, not orphaned with their text.
-- name: EmptyUserGroupMessages :exec
UPDATE group_messages SET body = '', mentions = '{}', mentions_agent = false,
    deleted_at = coalesce(deleted_at, now())
WHERE author_id = @user_id::uuid;

-- A group with nobody else in it goes.
-- name: DeleteSoloGroups :exec
DELETE FROM groups g WHERE g.id IN (SELECT m.group_id FROM group_members m WHERE m.user_id = @leaving_user_id::uuid)
  AND NOT EXISTS (SELECT 1 FROM group_members o WHERE o.group_id = g.id AND o.user_id <> @leaving_user_id::uuid);

-- name: DemoteOwnedGroups :many
UPDATE group_members SET role = 'admin' WHERE user_id = @user_id AND role = 'owner'
RETURNING group_id;

-- Each group the user owned passes to its oldest admin, else its oldest member.
-- name: PromoteNextOwner :exec
UPDATE group_members SET role = 'owner'
WHERE group_members.group_id = @group_id::uuid AND group_members.user_id = (
    SELECT m.user_id FROM group_members m
    WHERE m.group_id = @group_id::uuid AND m.user_id <> @leaving_user_id
    ORDER BY m.role = 'admin' DESC, m.joined_at, m.user_id LIMIT 1
);

-- A share link outlives its sender (SHR-002): the FK nulls the sender, and the note goes too.
-- name: ClearUserShareNotes :exec
UPDATE shares SET note = NULL WHERE sender_id = @user_id::uuid;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = @id;

-- Sessions.

-- name: CreateSession :exec
INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES (@id, @user_id, @token_hash, @expires_at);

-- name: DeleteSession :exec
DELETE FROM sessions WHERE token_hash = @token_hash;

-- Magic links and their 6-digit codes (AUTH-003, APP-002).

-- name: CreateMagicLink :exec
INSERT INTO magic_links (id, email, token_hash, code_hash, expires_at)
VALUES (@id, @email, @token_hash, @code_hash::text, @expires_at);

-- One statement: two concurrent verifies cannot both win.
-- name: ConsumeMagicLinkToken :one
UPDATE magic_links SET used_at = @now::pg_catalog.timestamptz
WHERE token_hash = @token_hash AND used_at IS NULL AND expires_at > @now::pg_catalog.timestamptz
RETURNING email;

-- name: ConsumeMagicLinkCode :one
UPDATE magic_links SET used_at = @now::pg_catalog.timestamptz
WHERE id = (
    SELECT l.id FROM magic_links l
    WHERE l.email = @email AND l.used_at IS NULL AND l.expires_at > @now::pg_catalog.timestamptz
      AND l.code_hash = @code_hash::text AND l.failed_attempts < @max_attempts
    ORDER BY l.created_at DESC LIMIT 1
    FOR UPDATE
) AND used_at IS NULL
RETURNING email;

-- A wrong code counts against every live link for the email.
-- name: FailMagicLinkCodes :exec
UPDATE magic_links SET failed_attempts = failed_attempts + 1
WHERE email = @email AND used_at IS NULL AND expires_at > @now::pg_catalog.timestamptz;
