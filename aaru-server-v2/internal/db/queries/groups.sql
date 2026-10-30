-- Groups, members, invites, channels, messages and read state (GRP-001…GRP-003), and the
-- social reads groups and the Board make on their own (PostgresGroupStore*.swift,
-- PostgresSocialStore.swift).

-- name: GroupSummaries :many
-- The viewer's groups in the order they joined them; one group with sqlc.narg(only_group).
-- Unread: messages from others since the viewer's read point, not deleted.
SELECT g.id, g.name, gm.role, gm.share_progress, gm.muted,
    (SELECT c0.id FROM group_channels c0 WHERE c0.group_id = g.id AND c0.is_default)::uuid AS default_channel_id,
    (SELECT count(*) FROM group_channels c JOIN group_messages m ON m.channel_id = c.id
        LEFT JOIN group_read_state r ON r.channel_id = c.id AND r.user_id = sqlc.arg(viewer)::uuid
        WHERE c.group_id = g.id AND m.deleted_at IS NULL AND m.author_id IS DISTINCT FROM sqlc.arg(viewer)::uuid
          AND m.created_at > coalesce(r.last_read_at, '-infinity'))::bigint AS unread,
    (SELECT count(*) FROM group_channels c JOIN group_messages m ON m.channel_id = c.id
        LEFT JOIN group_read_state r ON r.channel_id = c.id AND r.user_id = sqlc.arg(viewer)::uuid
        WHERE c.group_id = g.id AND m.deleted_at IS NULL AND m.author_id IS DISTINCT FROM sqlc.arg(viewer)::uuid
          AND m.created_at > coalesce(r.last_read_at, '-infinity')
          AND sqlc.arg(viewer)::uuid = ANY(m.mentions))::bigint AS mentions
FROM group_members gm JOIN groups g ON g.id = gm.group_id
WHERE gm.user_id = sqlc.arg(viewer)::uuid
  AND (sqlc.narg(only_group)::uuid IS NULL OR g.id = sqlc.narg(only_group)::uuid)
ORDER BY gm.joined_at, g.id;

-- name: GroupOwnedCount :one
SELECT count(*) FROM group_members WHERE user_id = $1 AND role = 'owner';

-- name: InsertGroup :exec
INSERT INTO groups (id, name, created_at, updated_at) VALUES ($1, $2, $3, $3);

-- name: InsertGroupMember :exec
INSERT INTO group_members (group_id, user_id, role, joined_at) VALUES ($1, $2, $3, $4)
ON CONFLICT DO NOTHING;

-- name: RenameGroup :exec
UPDATE groups SET name = $2, updated_at = $3 WHERE id = $1;

-- name: DeleteGroup :exec
DELETE FROM groups WHERE id = $1;

-- name: GroupMembers :many
SELECT gm.user_id, p.handle, u.display_name, u.avatar_version, gm.role, gm.joined_at, gm.share_progress
FROM group_members gm JOIN profiles p ON p.user_id = gm.user_id JOIN users u ON u.id = gm.user_id
WHERE gm.group_id = $1
ORDER BY gm.joined_at, p.handle;

-- name: GroupRole :one
SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2;

-- name: SetGroupRole :exec
UPDATE group_members SET role = $3 WHERE group_id = $1 AND user_id = $2;

-- name: DeleteGroupReadState :exec
DELETE FROM group_read_state WHERE user_id = $2
  AND channel_id IN (SELECT id FROM group_channels WHERE group_id = $1);

-- name: DeleteGroupMember :exec
DELETE FROM group_members WHERE group_id = $1 AND user_id = $2;

-- name: SetGroupMuted :exec
UPDATE group_members SET muted = $3 WHERE group_id = $1 AND user_id = $2;

-- name: SetGroupShareProgress :exec
UPDATE group_members SET share_progress = $3 WHERE group_id = $1 AND user_id = $2;

-- name: InsertGroupInvite :one
INSERT INTO group_invites (id, group_id, inviter_id, invitee_id, created_at)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (group_id, invitee_id) DO NOTHING RETURNING id;

-- name: GroupInvites :many
-- Invites to one user (sqlc.narg(invitee)) or in one group (sqlc.narg(in_group)), newest first.
SELECT i.id, i.group_id, g.name AS group_name, i.created_at,
       i.inviter_id, ip.handle AS inviter_handle, iu.display_name AS inviter_display_name,
       iu.avatar_version AS inviter_avatar_version,
       i.invitee_id, tp.handle AS invitee_handle, tu.display_name AS invitee_display_name,
       tu.avatar_version AS invitee_avatar_version
FROM group_invites i JOIN groups g ON g.id = i.group_id
JOIN profiles ip ON ip.user_id = i.inviter_id JOIN users iu ON iu.id = i.inviter_id
JOIN profiles tp ON tp.user_id = i.invitee_id JOIN users tu ON tu.id = i.invitee_id
WHERE (sqlc.narg(invitee)::uuid IS NULL OR i.invitee_id = sqlc.narg(invitee)::uuid)
  AND (sqlc.narg(in_group)::uuid IS NULL OR i.group_id = sqlc.narg(in_group)::uuid)
ORDER BY i.created_at DESC;

-- name: TakeGroupInvite :one
DELETE FROM group_invites WHERE id = $1 AND invitee_id = $2 RETURNING group_id;

-- name: MarkGroupReadOnJoin :exec
-- History before joining is not unread.
INSERT INTO group_read_state (user_id, channel_id, last_read_at)
SELECT sqlc.arg(user_id)::uuid, id, sqlc.arg(now)::pg_catalog.timestamptz FROM group_channels WHERE group_id = sqlc.arg(group_id)::uuid
ON CONFLICT DO NOTHING;

-- name: DeleteGroupInvite :one
DELETE FROM group_invites
WHERE id = sqlc.arg(id) AND (inviter_id = sqlc.arg(party)::uuid OR invitee_id = sqlc.arg(party)::uuid)
RETURNING group_id, invitee_id;

-- name: GroupChannels :many
SELECT c.id, c.group_id, c.kind, c.title_id, c.name, c.topic, c.position, c.is_default, c.created_at,
    (SELECT count(*) FROM group_messages m WHERE m.channel_id = c.id
        AND m.deleted_at IS NULL AND m.author_id IS DISTINCT FROM sqlc.arg(viewer)::uuid
        AND m.created_at > coalesce(r.last_read_at, '-infinity'))::bigint AS unread,
    (SELECT count(*) FROM group_messages m WHERE m.channel_id = c.id
        AND m.deleted_at IS NULL AND m.author_id IS DISTINCT FROM sqlc.arg(viewer)::uuid
        AND m.created_at > coalesce(r.last_read_at, '-infinity')
        AND sqlc.arg(viewer)::uuid = ANY(m.mentions))::bigint AS mentions
FROM group_channels c
LEFT JOIN group_read_state r ON r.channel_id = c.id AND r.user_id = sqlc.arg(viewer)::uuid
WHERE c.group_id = sqlc.arg(group_id)::uuid
ORDER BY c.position, c.created_at;

-- name: GroupChannel :one
SELECT id, group_id, kind, title_id, name, topic, position, is_default, created_at
FROM group_channels WHERE id = $1 AND group_id = $2;

-- name: InsertGroupChannel :exec
INSERT INTO group_channels (id, group_id, kind, title_id, name, topic, position, is_default, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);

-- name: UpdateGroupChannel :exec
-- A null name leaves it; set_topic replaces the topic with sqlc.narg(topic) (null clears it).
UPDATE group_channels SET name = coalesce(sqlc.narg(name), name),
    topic = CASE WHEN sqlc.arg(set_topic)::bool THEN sqlc.narg(topic) ELSE topic END
WHERE id = sqlc.arg(id);

-- name: DeleteGroupChannel :one
DELETE FROM group_channels WHERE id = $1 AND NOT is_default RETURNING id;

-- name: GroupMessage :one
SELECT m.id, m.channel_id, m.author_id, p.handle AS author_handle, u.display_name AS author_display_name,
    u.avatar_version AS author_avatar_version,
    m.body, m.mentions, m.mentions_agent, m.created_at, m.edited_at, m.deleted_at, m.client_nonce,
    m.spoiler_season, m.spoiler_episode, m.spoiler_ending, m.author_kind, m.reply_to, m.components
FROM group_messages m
LEFT JOIN profiles p ON p.user_id = m.author_id LEFT JOIN users u ON u.id = m.author_id
WHERE m.id = sqlc.arg(id) AND (sqlc.narg(channel_id)::uuid IS NULL OR m.channel_id = sqlc.narg(channel_id)::uuid);

-- name: GroupMessagesLatest :many
SELECT m.id, m.channel_id, m.author_id, p.handle AS author_handle, u.display_name AS author_display_name,
    u.avatar_version AS author_avatar_version,
    m.body, m.mentions, m.mentions_agent, m.created_at, m.edited_at, m.deleted_at, m.client_nonce,
    m.spoiler_season, m.spoiler_episode, m.spoiler_ending, m.author_kind, m.reply_to, m.components
FROM group_messages m
LEFT JOIN profiles p ON p.user_id = m.author_id LEFT JOIN users u ON u.id = m.author_id
WHERE m.channel_id = $1
ORDER BY m.created_at DESC, m.id DESC
LIMIT $2;

-- name: GroupMessagesBefore :many
SELECT m.id, m.channel_id, m.author_id, p.handle AS author_handle, u.display_name AS author_display_name,
    u.avatar_version AS author_avatar_version,
    m.body, m.mentions, m.mentions_agent, m.created_at, m.edited_at, m.deleted_at, m.client_nonce,
    m.spoiler_season, m.spoiler_episode, m.spoiler_ending, m.author_kind, m.reply_to, m.components
FROM group_messages m
LEFT JOIN profiles p ON p.user_id = m.author_id LEFT JOIN users u ON u.id = m.author_id
WHERE m.channel_id = sqlc.arg(channel_id)
  AND (m.created_at, m.id) < (SELECT a.created_at, a.id FROM group_messages a
      WHERE a.channel_id = sqlc.arg(channel_id) AND a.id = sqlc.arg(anchor))
ORDER BY m.created_at DESC, m.id DESC
LIMIT sqlc.arg(row_limit);

-- name: GroupMessagesAfter :many
SELECT m.id, m.channel_id, m.author_id, p.handle AS author_handle, u.display_name AS author_display_name,
    u.avatar_version AS author_avatar_version,
    m.body, m.mentions, m.mentions_agent, m.created_at, m.edited_at, m.deleted_at, m.client_nonce,
    m.spoiler_season, m.spoiler_episode, m.spoiler_ending, m.author_kind, m.reply_to, m.components
FROM group_messages m
LEFT JOIN profiles p ON p.user_id = m.author_id LEFT JOIN users u ON u.id = m.author_id
WHERE m.channel_id = sqlc.arg(channel_id)
  AND (m.created_at, m.id) > (SELECT a.created_at, a.id FROM group_messages a
      WHERE a.channel_id = sqlc.arg(channel_id) AND a.id = sqlc.arg(anchor))
ORDER BY m.created_at, m.id
LIMIT sqlc.arg(row_limit);

-- name: InsertGroupMessage :one
INSERT INTO group_messages (id, channel_id, author_id, body, mentions, mentions_agent, client_nonce, created_at,
                            spoiler_season, spoiler_episode, spoiler_ending, author_kind, reply_to, components)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
ON CONFLICT (author_id, client_nonce) DO NOTHING
RETURNING id;

-- name: GroupMessageByNonce :one
-- A retry: the nonce is unique per author, not per channel; one reused in another channel is a
-- conflict, never that other channel's message.
SELECT id FROM group_messages WHERE author_id = $1 AND client_nonce = $2 AND channel_id = $3;

-- name: EditGroupMessage :exec
UPDATE group_messages SET body = $2, mentions = $3, mentions_agent = $4, edited_at = $5
WHERE id = $1 AND deleted_at IS NULL;

-- name: DeleteGroupMessage :exec
UPDATE group_messages SET body = '', mentions = '{}', mentions_agent = false, deleted_at = $2
WHERE id = $1 AND deleted_at IS NULL;

-- name: MarkGroupChannelRead :exec
-- Moves the read point forward to that message; never backward.
INSERT INTO group_read_state (user_id, channel_id, last_read_at)
SELECT sqlc.arg(user_id)::uuid, gmsg.channel_id, gmsg.created_at FROM group_messages gmsg
WHERE gmsg.id = sqlc.arg(message_id)::uuid AND gmsg.channel_id = sqlc.arg(channel_id)::uuid
ON CONFLICT (user_id, channel_id) DO UPDATE
    SET last_read_at = GREATEST(group_read_state.last_read_at, EXCLUDED.last_read_at);

-- name: GroupTitleProgress :many
-- Each user's status in a title and the furthest episode they ticked (the tick no other tick
-- of the item is past).
SELECT li.user_id, li.status, ep.season, ep.episode
FROM library_items li
LEFT JOIN episode_progress ep ON ep.library_item_id = li.id AND NOT EXISTS (
    SELECT 1 FROM episode_progress e2 WHERE e2.library_item_id = li.id
      AND (e2.season, e2.episode) > (ep.season, ep.episode))
WHERE li.title_id = sqlc.arg(title_id) AND li.user_id = ANY(sqlc.arg(users)::uuid[]);

-- name: GroupShelfItems :many
SELECT i.title_id, i.added_by, p.handle, u.display_name, u.avatar_version, i.added_at, i.position,
    li.status AS my_status
FROM group_channel_items i
LEFT JOIN profiles p ON p.user_id = i.added_by LEFT JOIN users u ON u.id = i.added_by
LEFT JOIN library_items li ON li.title_id = i.title_id AND li.user_id = sqlc.arg(viewer)::uuid
WHERE i.channel_id = sqlc.arg(channel_id)
ORDER BY i.position, i.added_at;

-- name: AddGroupShelfItem :one
INSERT INTO group_channel_items (channel_id, title_id, added_by, position, added_at)
SELECT sqlc.arg(channel_id)::uuid, sqlc.arg(title_id)::uuid, sqlc.arg(added_by)::uuid,
       coalesce(max(position), 0) + 1, sqlc.arg(now)::pg_catalog.timestamptz
FROM group_channel_items WHERE channel_id = sqlc.arg(channel_id)::uuid
ON CONFLICT (channel_id, title_id) DO NOTHING
RETURNING title_id;

-- name: RemoveGroupShelfItem :one
DELETE FROM group_channel_items WHERE channel_id = $1 AND title_id = $2 RETURNING title_id;

-- name: LatestWatchParty :one
SELECT s.id, s.channel_id, s.title_id, s.season, s.episode, s.created_by, p.handle, u.display_name,
       u.avatar_version, s.starts_at, s.ended_at, s.created_at
FROM watch_sessions s
LEFT JOIN profiles p ON p.user_id = s.created_by LEFT JOIN users u ON u.id = s.created_by
WHERE s.channel_id = $1
ORDER BY s.created_at DESC LIMIT 1;

-- name: WatchPartyReady :many
SELECT r.user_id, p.handle, u.display_name, u.avatar_version
FROM watch_ready r JOIN profiles p ON p.user_id = r.user_id JOIN users u ON u.id = r.user_id
WHERE r.session_id = $1
ORDER BY p.handle;

-- name: InsertWatchParty :exec
INSERT INTO watch_sessions (id, channel_id, title_id, season, episode, created_by, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7);

-- name: SetWatchReady :exec
INSERT INTO watch_ready (session_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING;

-- name: UnsetWatchReady :exec
DELETE FROM watch_ready WHERE session_id = $1 AND user_id = $2;

-- name: StartWatchParty :exec
UPDATE watch_sessions SET starts_at = $2 WHERE id = $1 AND ended_at IS NULL;

-- name: EndWatchParty :exec
UPDATE watch_sessions SET ended_at = $2 WHERE id = $1 AND ended_at IS NULL;

-- Social reads (PostgresSocialStore). Groups and the Board read friendships and blocks themselves.

-- `@aaru` replies (GRP-010 / GRP-011, PostgresAgentStore).

-- name: EnqueueAgentReply :exec
INSERT INTO agent_replies (id, message_id, group_id, channel_id, tagger_id, state, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
ON CONFLICT (message_id) DO NOTHING;

-- name: GroupAgentLoad :one
-- States that count toward the caps: the model was, or will be, called.
SELECT
    (SELECT count(*) FROM agent_replies a WHERE a.tagger_id = sqlc.arg(tagger)::uuid
        AND a.created_at >= sqlc.arg(day_start)::pg_catalog.timestamptz
        AND a.state IN ('queued', 'running', 'done', 'failed'))::bigint AS user_today,
    (SELECT count(*) FROM agent_replies a WHERE a.group_id = sqlc.arg(group_id)::uuid
        AND a.created_at >= sqlc.arg(hour_start)::pg_catalog.timestamptz
        AND a.state IN ('queued', 'running', 'done', 'failed'))::bigint AS group_hour,
    EXISTS (SELECT 1 FROM agent_replies a WHERE a.tagger_id = sqlc.arg(tagger)::uuid
        AND a.created_at >= sqlc.arg(day_start)::pg_catalog.timestamptz AND a.state = 'capped') AS user_noted,
    EXISTS (SELECT 1 FROM agent_replies a WHERE a.group_id = sqlc.arg(group_id)::uuid
        AND a.created_at >= sqlc.arg(hour_start)::pg_catalog.timestamptz AND a.state = 'capped') AS group_noted;

-- name: ClaimAgentReply :one
-- One statement: SKIP LOCKED means two workers never lease the same mention.
UPDATE agent_replies SET state = 'running', attempts = attempts + 1,
    locked_until = sqlc.arg(locked_until)::pg_catalog.timestamptz, updated_at = sqlc.arg(now)::pg_catalog.timestamptz
WHERE id = (
    SELECT a.id FROM agent_replies a
    WHERE (a.state = 'queued' AND (a.locked_until IS NULL OR a.locked_until <= sqlc.arg(now)::pg_catalog.timestamptz))
       OR (a.state = 'running' AND a.locked_until < sqlc.arg(now)::pg_catalog.timestamptz)
    ORDER BY a.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
RETURNING id, message_id, group_id, channel_id, tagger_id, attempts;

-- name: FinishAgentReply :exec
UPDATE agent_replies SET state = $2, error = $3, locked_until = NULL, updated_at = $4 WHERE id = $1;

-- name: RetryAgentReply :exec
UPDATE agent_replies SET state = 'queued', error = $2, locked_until = $3, updated_at = $4 WHERE id = $1;

-- name: RecordAgentUsage :exec
INSERT INTO agent_usage (user_id, day, requests, input_tokens, output_tokens, cost_micros)
VALUES (sqlc.arg(user_id), (sqlc.arg(at)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::date, 1, sqlc.arg(input_tokens),
        sqlc.arg(output_tokens), sqlc.arg(cost_micros))
ON CONFLICT (user_id, day) DO UPDATE SET requests = agent_usage.requests + 1,
    input_tokens = agent_usage.input_tokens + EXCLUDED.input_tokens,
    output_tokens = agent_usage.output_tokens + EXCLUDED.output_tokens,
    cost_micros = agent_usage.cost_micros + EXCLUDED.cost_micros;

-- name: AgentUsageOn :one
SELECT requests, input_tokens, output_tokens, cost_micros FROM agent_usage
WHERE user_id = sqlc.arg(user_id) AND day = (sqlc.arg(at)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::date;
