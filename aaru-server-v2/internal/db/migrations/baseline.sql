CREATE TABLE actions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    actor text NOT NULL,
    kind text NOT NULL,
    summary text NOT NULL,
    item_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    inverse jsonb NOT NULL,
    undo_of uuid,
    undone_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    agent_token_id uuid,
    CONSTRAINT actions_actor_check CHECK ((actor = ANY (ARRAY['user'::text, 'agent'::text, 'external_agent'::text])))
);

CREATE TABLE agent_plans (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    agent_token_id uuid,
    agent_name text NOT NULL,
    status text NOT NULL,
    summary text NOT NULL,
    changes jsonb NOT NULL,
    counts jsonb NOT NULL,
    op jsonb NOT NULL,
    basis jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    decided_at timestamp with time zone,
    action_id uuid,
    CONSTRAINT agent_plans_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'applied'::text, 'denied'::text, 'stale'::text, 'expired'::text])))
);

CREATE TABLE agent_replies (
    id uuid NOT NULL,
    message_id uuid NOT NULL,
    group_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    tagger_id uuid NOT NULL,
    state text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    error text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT agent_replies_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'running'::text, 'done'::text, 'failed'::text, 'capped'::text, 'skipped'::text])))
);

CREATE TABLE agent_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    token_hash text NOT NULL,
    scopes text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    issuance text DEFAULT 'secret'::text NOT NULL,
    oauth_client_id text,
    CONSTRAINT agent_tokens_issuance_check CHECK ((issuance = ANY (ARRAY['secret'::text, 'oauth'::text]))),
    CONSTRAINT agent_tokens_kind_check CHECK ((kind = ANY (ARRAY['stremio'::text, 'claude_code'::text, 'codex'::text, 'hermes'::text, 'gemini'::text, 'other'::text, 'claude'::text, 'browser'::text, 'music'::text]))),
    CONSTRAINT agent_tokens_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 80))),
    CONSTRAINT agent_tokens_scopes_check CHECK ((scopes <@ ARRAY['library:read'::text, 'library:write'::text, 'scrobble:write'::text, 'imports:write'::text]))
);

CREATE TABLE agent_usage (
    user_id uuid NOT NULL,
    day date NOT NULL,
    requests integer DEFAULT 0 NOT NULL,
    input_tokens bigint DEFAULT 0 NOT NULL,
    output_tokens bigint DEFAULT 0 NOT NULL,
    cost_micros bigint DEFAULT 0 NOT NULL
);

CREATE TABLE album_artists (
    title_id uuid NOT NULL,
    artist text NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT album_artists_position_check CHECK (("position" >= 0))
);

CREATE TABLE album_tracks (
    title_id uuid NOT NULL,
    disc integer NOT NULL,
    "position" integer NOT NULL,
    name text NOT NULL,
    length_ms integer,
    CONSTRAINT album_tracks_disc_check CHECK ((disc >= 1)),
    CONSTRAINT album_tracks_length_ms_check CHECK ((length_ms >= 0)),
    CONSTRAINT album_tracks_position_check CHECK (("position" >= 1))
);

CREATE TABLE anime_mappings (
    anilist text NOT NULL,
    mal text,
    anidb text,
    tvdb text,
    tmdb text,
    tmdb_season integer
);

CREATE TABLE apns_devices (
    token text NOT NULL,
    user_id uuid NOT NULL,
    environment text NOT NULL,
    topic text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT apns_devices_environment_check CHECK ((environment = ANY (ARRAY['sandbox'::text, 'production'::text])))
);

CREATE TABLE auth_identities (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    provider text NOT NULL,
    provider_subject text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT auth_identities_provider_check CHECK ((provider = ANY (ARRAY['apple'::text, 'email'::text, 'google'::text])))
);

CREATE TABLE avatars (
    user_id uuid NOT NULL,
    image bytea NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT avatars_image_check CHECK ((octet_length(image) <= 1048576))
);

CREATE TABLE board_comments (
    id uuid NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid,
    author_kind text NOT NULL,
    reply_to uuid,
    body text NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    mentions_agent boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT board_comments_author_bound CHECK (((author_kind = 'user'::text) = (user_id IS NOT NULL))),
    CONSTRAINT board_comments_author_kind_check CHECK ((author_kind = ANY (ARRAY['user'::text, 'agent'::text]))),
    CONSTRAINT board_comments_body_check CHECK ((char_length(body) <= 4000))
);

CREATE TABLE board_posts (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    title_id uuid,
    rating numeric(3,1),
    body text NOT NULL,
    spoiler_season integer,
    spoiler_episode integer,
    spoiler_ending boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    edited_at timestamp with time zone,
    deleted_at timestamp with time zone,
    CONSTRAINT board_posts_body_check CHECK ((char_length(body) <= 4000)),
    CONSTRAINT board_posts_check CHECK (((rating IS NULL) OR (title_id IS NOT NULL))),
    CONSTRAINT board_posts_rating_check CHECK (((rating IS NULL) OR ((rating >= (1)::numeric) AND (rating <= (10)::numeric)))),
    CONSTRAINT board_posts_spoiler_episode_check CHECK ((spoiler_episode >= 1)),
    CONSTRAINT board_posts_spoiler_pair CHECK (((spoiler_season IS NULL) = (spoiler_episode IS NULL))),
    CONSTRAINT board_posts_spoiler_season_check CHECK ((spoiler_season >= 0))
);

CREATE TABLE board_upvotes (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE capture_inputs (
    job_id uuid NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    text text,
    image bytea,
    media_type text,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT capture_inputs_kind_check CHECK ((kind = ANY (ARRAY['text'::text, 'image'::text])))
);

CREATE TABLE check_ins (
    user_id uuid NOT NULL,
    local_date date NOT NULL,
    time_zone text NOT NULL,
    first_at timestamp with time zone NOT NULL
);

CREATE TABLE concert_places (
    user_id uuid NOT NULL,
    name text NOT NULL,
    region text,
    country text,
    country_code text,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT concert_places_country_check CHECK (((char_length(country) >= 1) AND (char_length(country) <= 200))),
    CONSTRAINT concert_places_country_code_check CHECK ((char_length(country_code) = 2)),
    CONSTRAINT concert_places_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
    CONSTRAINT concert_places_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
    CONSTRAINT concert_places_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 200))),
    CONSTRAINT concert_places_region_check CHECK (((char_length(region) >= 1) AND (char_length(region) <= 200)))
);

CREATE TABLE entitlements (
    original_transaction_id text NOT NULL,
    user_id uuid NOT NULL,
    product_id text NOT NULL,
    environment text NOT NULL,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    signed_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);

CREATE TABLE episode_progress (
    id uuid NOT NULL,
    library_item_id uuid NOT NULL,
    season integer NOT NULL,
    episode integer NOT NULL,
    watched_at timestamp with time zone DEFAULT now() NOT NULL,
    watched_at_known boolean DEFAULT true NOT NULL,
    CONSTRAINT episode_progress_episode_check CHECK ((episode >= 1)),
    CONSTRAINT episode_progress_season_check CHECK ((season >= 0))
);

CREATE TABLE favorites (
    user_id uuid NOT NULL,
    kind text NOT NULL,
    "position" integer NOT NULL,
    title_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT favorites_kind_check CHECK ((kind = ANY (ARRAY['film'::text, 'show'::text, 'anime'::text, 'manga'::text, 'book'::text, 'album'::text]))),
    CONSTRAINT favorites_position_check CHECK ((("position" >= 0) AND ("position" <= 9)))
);

CREATE TABLE group_channel_items (
    channel_id uuid NOT NULL,
    title_id uuid NOT NULL,
    added_by uuid,
    "position" integer NOT NULL,
    added_at timestamp with time zone NOT NULL
);

CREATE TABLE group_channels (
    id uuid NOT NULL,
    group_id uuid NOT NULL,
    kind text NOT NULL,
    name text NOT NULL,
    topic text,
    "position" integer NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone NOT NULL,
    title_id uuid,
    CONSTRAINT group_channels_kind_check CHECK ((kind = ANY (ARRAY['text'::text, 'title'::text, 'watch'::text, 'shelf'::text]))),
    CONSTRAINT group_channels_name_check CHECK ((((char_length(name) >= 1) AND (char_length(name) <= 32)) AND (name !~ '\s'::text))),
    CONSTRAINT group_channels_title_bound CHECK (((kind = 'title'::text) = (title_id IS NOT NULL))),
    CONSTRAINT group_channels_topic_check CHECK ((char_length(topic) <= 200))
);

CREATE TABLE group_invites (
    id uuid NOT NULL,
    group_id uuid NOT NULL,
    inviter_id uuid NOT NULL,
    invitee_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT group_invites_check CHECK ((inviter_id <> invitee_id))
);

CREATE TABLE group_members (
    group_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    joined_at timestamp with time zone NOT NULL,
    share_progress boolean DEFAULT false NOT NULL,
    muted boolean DEFAULT false NOT NULL,
    CONSTRAINT group_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text])))
);

CREATE TABLE group_messages (
    id uuid NOT NULL,
    channel_id uuid NOT NULL,
    author_id uuid,
    body text NOT NULL,
    mentions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    mentions_agent boolean DEFAULT false NOT NULL,
    client_nonce text,
    created_at timestamp with time zone NOT NULL,
    edited_at timestamp with time zone,
    deleted_at timestamp with time zone,
    spoiler_season integer,
    spoiler_episode integer,
    spoiler_ending boolean DEFAULT false NOT NULL,
    author_kind text DEFAULT 'user'::text NOT NULL,
    reply_to uuid,
    components jsonb,
    CONSTRAINT group_messages_agent_has_no_author CHECK (((author_kind = 'user'::text) OR (author_id IS NULL))),
    CONSTRAINT group_messages_author_kind_check CHECK ((author_kind = ANY (ARRAY['user'::text, 'agent'::text]))),
    CONSTRAINT group_messages_body_check CHECK ((char_length(body) <= 4000)),
    CONSTRAINT group_messages_client_nonce_check CHECK ((char_length(client_nonce) <= 64)),
    CONSTRAINT group_messages_spoiler_episode_check CHECK ((spoiler_episode >= 1)),
    CONSTRAINT group_messages_spoiler_pair CHECK (((spoiler_season IS NULL) = (spoiler_episode IS NULL))),
    CONSTRAINT group_messages_spoiler_season_check CHECK ((spoiler_season >= 0))
);

CREATE TABLE group_read_state (
    user_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    last_read_at timestamp with time zone NOT NULL
);

CREATE TABLE groups (
    id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT groups_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 50)))
);

CREATE TABLE import_jobs (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    source text NOT NULL,
    state text NOT NULL,
    stats jsonb NOT NULL,
    error_summary text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    filename text,
    attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    rows_matched integer DEFAULT 0 NOT NULL,
    action_id uuid,
    CONSTRAINT import_jobs_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'running'::text, 'planned'::text, 'succeeded'::text, 'failed'::text, 'partial'::text])))
);

CREATE TABLE import_listens (
    job_id uuid NOT NULL,
    idx integer NOT NULL,
    listened_at timestamp with time zone NOT NULL,
    artist text NOT NULL,
    track text NOT NULL,
    album text,
    track_key text NOT NULL,
    duration_ms integer,
    isrc text,
    recording_mbid text,
    release_mbid text,
    release_group_mbid text,
    artist_mbid text,
    spotify_id text,
    origin_url text,
    client text,
    music_service text,
    CONSTRAINT import_listens_album_check CHECK (((char_length(album) >= 1) AND (char_length(album) <= 500))),
    CONSTRAINT import_listens_artist_check CHECK (((char_length(artist) >= 1) AND (char_length(artist) <= 500))),
    CONSTRAINT import_listens_duration_ms_check CHECK ((duration_ms > 0)),
    CONSTRAINT import_listens_track_check CHECK (((char_length(track) >= 1) AND (char_length(track) <= 500)))
);

CREATE TABLE import_rows (
    job_id uuid NOT NULL,
    idx integer NOT NULL,
    "row" jsonb NOT NULL,
    outcome text DEFAULT 'pending'::text NOT NULL,
    reason text,
    title_id uuid,
    CONSTRAINT import_rows_outcome_check CHECK ((outcome = ANY (ARRAY['pending'::text, 'create'::text, 'update'::text, 'skip'::text, 'unmatched'::text])))
);

CREATE TABLE library_items (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    title_id uuid NOT NULL,
    status text NOT NULL,
    is_owned boolean DEFAULT false NOT NULL,
    rating double precision,
    notes text,
    added_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    book_page integer,
    book_percent double precision,
    status_by_hand boolean DEFAULT false NOT NULL,
    manga_chapter integer,
    manga_volume integer,
    CONSTRAINT library_items_book_page_check CHECK ((book_page >= 0)),
    CONSTRAINT library_items_book_percent_check CHECK (((book_percent >= (0)::double precision) AND (book_percent <= (100)::double precision))),
    CONSTRAINT library_items_manga_chapter_check CHECK ((manga_chapter >= 0)),
    CONSTRAINT library_items_manga_volume_check CHECK ((manga_volume >= 0)),
    CONSTRAINT library_items_one_book_progress CHECK (((book_page IS NULL) OR (book_percent IS NULL))),
    CONSTRAINT library_items_rating_check CHECK ((((rating >= (1)::double precision) AND (rating <= (10)::double precision)) AND ((rating * (2)::double precision) = floor((rating * (2)::double precision))))),
    CONSTRAINT library_items_status_check CHECK ((status = ANY (ARRAY['wishlist'::text, 'in_progress'::text, 'on_hold'::text, 'finished'::text, 'dropped'::text])))
);

CREATE TABLE library_tombstones (
    user_id uuid NOT NULL,
    library_item_id uuid NOT NULL,
    deleted_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE list_items (
    id uuid NOT NULL,
    list_id uuid NOT NULL,
    title_id uuid NOT NULL,
    "position" integer NOT NULL,
    added_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE listens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    listened_at timestamp with time zone NOT NULL,
    artist text NOT NULL,
    track text NOT NULL,
    album text,
    track_key text NOT NULL,
    duration_ms integer,
    isrc text,
    recording_mbid text,
    release_mbid text,
    release_group_mbid text,
    artist_mbid text,
    spotify_id text,
    origin_url text,
    client text,
    music_service text,
    source text NOT NULL,
    agent_token_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    import_job_id uuid,
    CONSTRAINT listens_album_check CHECK (((char_length(album) >= 1) AND (char_length(album) <= 500))),
    CONSTRAINT listens_artist_check CHECK (((char_length(artist) >= 1) AND (char_length(artist) <= 500))),
    CONSTRAINT listens_duration_ms_check CHECK ((duration_ms > 0)),
    CONSTRAINT listens_source_check CHECK ((source = ANY (ARRAY['live'::text, 'import'::text]))),
    CONSTRAINT listens_track_check CHECK (((char_length(track) >= 1) AND (char_length(track) <= 500)))
);

CREATE TABLE lists (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    visibility text DEFAULT 'private'::text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT lists_name_check CHECK ((btrim(name) <> ''::text)),
    CONSTRAINT lists_visibility_check CHECK ((visibility = 'private'::text))
);

CREATE TABLE live_activity_states (
    user_id uuid NOT NULL,
    pushed jsonb,
    lingering jsonb DEFAULT '[]'::jsonb NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    next_check_at timestamp with time zone
);

CREATE TABLE live_activity_tokens (
    token text NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    environment text NOT NULL,
    topic text NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT live_activity_tokens_environment_check CHECK ((environment = ANY (ARRAY['sandbox'::text, 'production'::text]))),
    CONSTRAINT live_activity_tokens_kind_check CHECK ((kind = ANY (ARRAY['start'::text, 'update'::text])))
);

CREATE TABLE live_plays (
    user_id uuid NOT NULL,
    agent_token_id uuid NOT NULL,
    kind text NOT NULL,
    id uuid NOT NULL,
    source text NOT NULL,
    ref text NOT NULL,
    title text NOT NULL,
    subtitle text,
    service text,
    artwork_url text,
    origin_url text,
    state text NOT NULL,
    position_ms bigint NOT NULL,
    duration_ms bigint NOT NULL,
    started_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT live_plays_kind_check CHECK ((kind = ANY (ARRAY['track'::text, 'video'::text]))),
    CONSTRAINT live_plays_source_check CHECK ((source = ANY (ARRAY['listenbrainz'::text, 'youtube'::text]))),
    CONSTRAINT live_plays_state_check CHECK ((state = ANY (ARRAY['playing'::text, 'paused'::text])))
);

CREATE TABLE magic_links (
    id uuid NOT NULL,
    email text NOT NULL,
    token_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    code_hash text,
    failed_attempts integer DEFAULT 0 NOT NULL
);

CREATE TABLE mal_auth_requests (
    state_hash text NOT NULL,
    user_id uuid NOT NULL,
    code_verifier text NOT NULL,
    return_to text NOT NULL,
    expires_at timestamp with time zone NOT NULL
);

CREATE TABLE mal_connections (
    user_id uuid NOT NULL,
    access_token text NOT NULL,
    refresh_token text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    username text,
    connected_at timestamp with time zone DEFAULT now() NOT NULL,
    push_cursor timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    pull_cursor timestamp with time zone,
    pulled_at timestamp with time zone,
    pull_requested_at timestamp with time zone,
    full_read_at timestamp with time zone
);

CREATE TABLE mal_entry_states (
    user_id uuid NOT NULL,
    mal_id text NOT NULL,
    status text NOT NULL,
    episodes integer NOT NULL,
    score integer NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    title text,
    removed_at timestamp with time zone,
    CONSTRAINT mal_entry_states_episodes_check CHECK ((episodes >= 0)),
    CONSTRAINT mal_entry_states_score_check CHECK (((score >= 0) AND (score <= 10))),
    CONSTRAINT mal_entry_states_status_check CHECK ((status = ANY (ARRAY['watching'::text, 'completed'::text, 'on_hold'::text, 'dropped'::text, 'plan_to_watch'::text])))
);

CREATE TABLE music_artists (
    musicbrainz text NOT NULL,
    name text NOT NULL,
    performer_id text,
    matched_at timestamp with time zone,
    CONSTRAINT music_artists_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 500)))
);

CREATE TABLE music_lookups (
    track_key text NOT NULL,
    album_key text NOT NULL,
    recording_mbid text,
    release_group_mbid text,
    artist_mbid text,
    looked_up_at timestamp with time zone NOT NULL
);

CREATE TABLE notification_settings (
    user_id uuid NOT NULL,
    airing boolean DEFAULT false NOT NULL,
    airing_since timestamp with time zone,
    group_mentions boolean DEFAULT false NOT NULL,
    group_invites boolean DEFAULT false NOT NULL
);

CREATE TABLE notifications_sent (
    user_id uuid NOT NULL,
    title_id uuid NOT NULL,
    season integer NOT NULL,
    episode integer NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE oauth_clients (
    id text NOT NULL,
    name text NOT NULL,
    redirect_uris text[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE oauth_codes (
    code_hash text NOT NULL,
    client_id text NOT NULL,
    user_id uuid NOT NULL,
    redirect_uri text NOT NULL,
    code_challenge text NOT NULL,
    resource text,
    name text NOT NULL,
    kind text NOT NULL,
    allow_writes boolean NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone,
    agent_token_id uuid
);

CREATE TABLE oauth_refresh_tokens (
    token_hash text NOT NULL,
    agent_token_id uuid NOT NULL,
    client_id text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone
);

CREATE TABLE oauth_requests (
    id uuid NOT NULL,
    client_id text NOT NULL,
    redirect_uri text NOT NULL,
    state text,
    code_challenge text NOT NULL,
    resource text,
    binding_hash text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    consumed_at timestamp with time zone
);

CREATE TABLE points_events (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    points integer NOT NULL,
    dedupe_root text NOT NULL,
    seq integer NOT NULL,
    dedupe_key text NOT NULL,
    reverses uuid,
    title_id uuid,
    action_id uuid,
    local_date date NOT NULL,
    time_zone text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT points_events_seq_check CHECK ((seq >= 1))
);

CREATE TABLE profiles (
    user_id uuid NOT NULL,
    handle text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_handle_check CHECK ((handle ~ '^[a-z0-9_]{3,20}$'::text))
);

CREATE TABLE saved_queries (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    filter jsonb NOT NULL,
    is_pinned boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT saved_queries_name_check CHECK ((btrim(name) <> ''::text))
);

CREATE TABLE sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);

CREATE TABLE shares (
    code text NOT NULL,
    sender_id uuid,
    kind text NOT NULL,
    title_id uuid,
    sport_event_id text,
    concert_id text,
    note text,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT shares_check CHECK ((((kind = 'title'::text) = (title_id IS NOT NULL)) AND ((kind = 'sport_event'::text) = (sport_event_id IS NOT NULL)) AND ((kind = 'concert'::text) = (concert_id IS NOT NULL)))),
    CONSTRAINT shares_kind_check CHECK ((kind = ANY (ARRAY['title'::text, 'sport_event'::text, 'concert'::text]))),
    CONSTRAINT shares_note_check CHECK (((note IS NULL) OR (char_length(note) <= 140)))
);

CREATE TABLE show_episodes (
    id uuid NOT NULL,
    title_id uuid NOT NULL,
    season integer NOT NULL,
    episode integer NOT NULL,
    name text,
    airs_at timestamp with time zone,
    tmdb_episode_id text,
    runtime_minutes integer,
    airs_at_exact boolean DEFAULT false NOT NULL,
    overview text,
    still_url text,
    CONSTRAINT show_episodes_episode_check CHECK ((episode >= 1)),
    CONSTRAINT show_episodes_season_check CHECK ((season >= 0))
);

CREATE TABLE social_blocks (
    blocker_id uuid NOT NULL,
    blocked_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT social_blocks_check CHECK ((blocker_id <> blocked_id))
);

CREATE TABLE social_friend_requests (
    id uuid NOT NULL,
    from_user_id uuid NOT NULL,
    to_user_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT social_friend_requests_check CHECK ((from_user_id <> to_user_id))
);

CREATE TABLE social_friendships (
    user_low uuid NOT NULL,
    user_high uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT social_friendships_check CHECK ((user_low < user_high))
);

CREATE TABLE social_invites (
    id uuid NOT NULL,
    code text NOT NULL,
    inviter_id uuid NOT NULL,
    title_id uuid,
    created_at timestamp with time zone NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    redeemed_by uuid,
    redeemed_at timestamp with time zone,
    revoked_at timestamp with time zone,
    CONSTRAINT social_invites_check CHECK (((redeemed_by IS NULL) OR (redeemed_by <> inviter_id)))
);

CREATE TABLE social_reactions (
    user_id uuid NOT NULL,
    owner_id uuid NOT NULL,
    title_id uuid NOT NULL,
    day date NOT NULL,
    emoji text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT social_reactions_emoji_check CHECK ((emoji = ANY (ARRAY['❤️'::text, '😂'::text, '😮'::text, '😭'::text, '🔥'::text, '👏'::text])))
);

CREATE TABLE social_recommendations (
    id uuid NOT NULL,
    from_user_id uuid NOT NULL,
    to_user_id uuid NOT NULL,
    title_id uuid NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL,
    added_at timestamp with time zone,
    dismissed_at timestamp with time zone,
    CONSTRAINT social_recommendations_check CHECK ((from_user_id <> to_user_id)),
    CONSTRAINT social_recommendations_note_check CHECK ((char_length(note) <= 140))
);

CREATE TABLE social_reports (
    id uuid NOT NULL,
    reporter_id uuid NOT NULL,
    target_user_id uuid,
    reason text NOT NULL,
    note text,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT social_reports_note_check CHECK ((char_length(note) <= 1000)),
    CONSTRAINT social_reports_reason_check CHECK ((reason = ANY (ARRAY['spam'::text, 'harassment'::text, 'impersonation'::text, 'other'::text])))
);

CREATE TABLE social_settings (
    user_id uuid NOT NULL,
    share_library_with_friends boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    show_achievements_to_friends boolean DEFAULT true NOT NULL,
    leaderboard_opt_in boolean DEFAULT false NOT NULL,
    share_email_with_friends boolean DEFAULT false NOT NULL
);

CREATE TABLE sport_follows (
    user_id uuid NOT NULL,
    kind text NOT NULL,
    provider_id text NOT NULL,
    name text NOT NULL,
    sport text NOT NULL,
    badge_url text,
    country text,
    league_id text,
    team_id text,
    team_name text,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT sport_follows_badge_url_check CHECK ((char_length(badge_url) <= 1000)),
    CONSTRAINT sport_follows_country_check CHECK ((char_length(country) <= 200)),
    CONSTRAINT sport_follows_kind_check CHECK ((kind = ANY (ARRAY['league'::text, 'team'::text, 'player'::text]))),
    CONSTRAINT sport_follows_league_id_check CHECK ((char_length(league_id) <= 40)),
    CONSTRAINT sport_follows_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 300))),
    CONSTRAINT sport_follows_provider_id_check CHECK (((char_length(provider_id) >= 1) AND (char_length(provider_id) <= 40))),
    CONSTRAINT sport_follows_sport_check CHECK ((char_length(sport) <= 100)),
    CONSTRAINT sport_follows_team_id_check CHECK ((char_length(team_id) <= 40)),
    CONSTRAINT sport_follows_team_name_check CHECK ((char_length(team_name) <= 300))
);

CREATE TABLE sport_settings (
    user_id uuid NOT NULL,
    watch_country_code text,
    updated_at timestamp with time zone NOT NULL,
    CONSTRAINT sport_settings_watch_country_code_check CHECK ((char_length(watch_country_code) = 2))
);

CREATE TABLE stremio_link_requests (
    code text NOT NULL,
    user_id uuid NOT NULL,
    expires_at timestamp with time zone NOT NULL
);

CREATE TABLE titles (
    id uuid NOT NULL,
    type text NOT NULL,
    title text NOT NULL,
    original_title text,
    year integer,
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    is_anime boolean DEFAULT false NOT NULL,
    status text,
    runtime_minutes integer,
    episodes_hydrated_at timestamp with time zone,
    backdrop_url text,
    network text,
    episodes_attempted_at timestamp with time zone,
    genres text[] DEFAULT '{}'::text[] NOT NULL,
    genres_attempted_at timestamp with time zone,
    musicbrainz text,
    byline text,
    tracks_hydrated_at timestamp with time zone,
    artists_checked_at timestamp with time zone,
    page_count integer,
    page_count_attempted_at timestamp with time zone,
    chapter_count integer,
    volume_count integer,
    CONSTRAINT titles_chapter_count_check CHECK ((chapter_count > 0)),
    CONSTRAINT titles_page_count_check CHECK ((page_count > 0)),
    CONSTRAINT titles_status_check CHECK ((status = ANY (ARRAY['upcoming'::text, 'returning'::text, 'ended'::text, 'canceled'::text]))),
    CONSTRAINT titles_title_check CHECK ((btrim(title) <> ''::text)),
    CONSTRAINT titles_type_check CHECK ((type = ANY (ARRAY['movie'::text, 'show'::text, 'book'::text, 'album'::text, 'manga'::text]))),
    CONSTRAINT titles_volume_count_check CHECK ((volume_count > 0)),
    CONSTRAINT titles_year_check CHECK (((year >= 1870) AND (year <= 2200)))
);

CREATE TABLE tonight_feedback (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    library_item_id uuid NOT NULL,
    verdict text NOT NULL,
    day date NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT tonight_feedback_verdict_check CHECK ((verdict = ANY (ARRAY['rejected'::text, 'not_tonight'::text])))
);

CREATE TABLE tonight_picks (
    user_id uuid NOT NULL,
    day date NOT NULL,
    library_item_id uuid NOT NULL,
    rank smallint NOT NULL,
    served_at timestamp with time zone NOT NULL,
    accepted_at timestamp with time zone
);

CREATE TABLE trakt_auth_requests (
    state_hash text NOT NULL,
    user_id uuid NOT NULL,
    code_verifier text NOT NULL,
    return_to text NOT NULL,
    expires_at timestamp with time zone NOT NULL
);

CREATE TABLE trakt_connections (
    user_id uuid NOT NULL,
    access_token text NOT NULL,
    refresh_token text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    username text,
    connected_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE user_badges (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    badge text NOT NULL,
    tier integer NOT NULL,
    awarded_at timestamp with time zone NOT NULL,
    origin text NOT NULL,
    action_id uuid,
    seen_at timestamp with time zone,
    CONSTRAINT user_badges_origin_check CHECK ((origin = ANY (ARRAY['live'::text, 'batch'::text, 'backfill'::text]))),
    CONSTRAINT user_badges_tier_check CHECK (((tier >= 1) AND (tier <= 4)))
);

CREATE TABLE user_progress (
    user_id uuid NOT NULL,
    total_points integer DEFAULT 0 NOT NULL,
    time_zone text,
    dirty_at timestamp with time zone,
    dirty_origin text,
    locked_until timestamp with time zone,
    evaluated_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_progress_dirty_origin_check CHECK ((dirty_origin = ANY (ARRAY['live'::text, 'batch'::text, 'backfill'::text])))
);

CREATE TABLE users (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    display_name text,
    first_name text,
    last_name text,
    avatar_version bigint
);

CREATE TABLE watch_events (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    agent_token_id uuid,
    source text NOT NULL,
    external_ref text NOT NULL,
    title_id uuid,
    season integer,
    episode integer,
    state text NOT NULL,
    position_ms bigint DEFAULT 0 NOT NULL,
    duration_ms bigint DEFAULT 0 NOT NULL,
    started_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    stopped_at timestamp with time zone,
    CONSTRAINT watch_events_source_check CHECK ((source = ANY (ARRAY['stremio'::text, 'netflix'::text, 'disney_plus'::text, 'prime_video'::text]))),
    CONSTRAINT watch_events_state_check CHECK ((state = ANY (ARRAY['playing'::text, 'paused'::text, 'stopped'::text])))
);

CREATE TABLE watch_ready (
    session_id uuid NOT NULL,
    user_id uuid NOT NULL
);

CREATE TABLE watch_sessions (
    id uuid NOT NULL,
    channel_id uuid NOT NULL,
    title_id uuid NOT NULL,
    season integer,
    episode integer,
    created_by uuid,
    starts_at timestamp with time zone,
    ended_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT watch_sessions_check CHECK (((season IS NULL) = (episode IS NULL))),
    CONSTRAINT watch_sessions_episode_check CHECK ((episode >= 1)),
    CONSTRAINT watch_sessions_season_check CHECK ((season >= 0))
);

CREATE TABLE web_push_subscriptions (
    endpoint text NOT NULL,
    user_id uuid NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    vapid_key_id text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY agent_plans
    ADD CONSTRAINT agent_plans_pkey PRIMARY KEY (id);

ALTER TABLE ONLY agent_replies
    ADD CONSTRAINT agent_replies_message_id_key UNIQUE (message_id);

ALTER TABLE ONLY agent_replies
    ADD CONSTRAINT agent_replies_pkey PRIMARY KEY (id);

ALTER TABLE ONLY agent_tokens
    ADD CONSTRAINT agent_tokens_pkey PRIMARY KEY (id);

ALTER TABLE ONLY agent_tokens
    ADD CONSTRAINT agent_tokens_token_hash_key UNIQUE (token_hash);

ALTER TABLE ONLY agent_usage
    ADD CONSTRAINT agent_usage_pkey PRIMARY KEY (user_id, day);

ALTER TABLE ONLY album_artists
    ADD CONSTRAINT album_artists_pkey PRIMARY KEY (title_id, artist);

ALTER TABLE ONLY album_tracks
    ADD CONSTRAINT album_tracks_pkey PRIMARY KEY (title_id, disc, "position");

ALTER TABLE ONLY anime_mappings
    ADD CONSTRAINT anime_mappings_pkey PRIMARY KEY (anilist);

ALTER TABLE ONLY apns_devices
    ADD CONSTRAINT apns_devices_pkey PRIMARY KEY (token);

ALTER TABLE ONLY auth_identities
    ADD CONSTRAINT auth_identities_pkey PRIMARY KEY (id);

ALTER TABLE ONLY auth_identities
    ADD CONSTRAINT auth_identities_provider_provider_subject_key UNIQUE (provider, provider_subject);

ALTER TABLE ONLY avatars
    ADD CONSTRAINT avatars_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY board_comments
    ADD CONSTRAINT board_comments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY board_posts
    ADD CONSTRAINT board_posts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY board_upvotes
    ADD CONSTRAINT board_upvotes_pkey PRIMARY KEY (post_id, user_id);

ALTER TABLE ONLY capture_inputs
    ADD CONSTRAINT capture_inputs_pkey PRIMARY KEY (job_id);

ALTER TABLE ONLY check_ins
    ADD CONSTRAINT check_ins_pkey PRIMARY KEY (user_id, local_date);

ALTER TABLE ONLY concert_places
    ADD CONSTRAINT concert_places_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY entitlements
    ADD CONSTRAINT entitlements_pkey PRIMARY KEY (original_transaction_id);

ALTER TABLE ONLY episode_progress
    ADD CONSTRAINT episode_progress_library_item_id_season_episode_key UNIQUE (library_item_id, season, episode);

ALTER TABLE ONLY episode_progress
    ADD CONSTRAINT episode_progress_pkey PRIMARY KEY (id);

ALTER TABLE ONLY favorites
    ADD CONSTRAINT favorites_pkey PRIMARY KEY (user_id, kind, "position");

ALTER TABLE ONLY favorites
    ADD CONSTRAINT favorites_user_id_kind_title_id_key UNIQUE (user_id, kind, title_id);

ALTER TABLE ONLY group_channel_items
    ADD CONSTRAINT group_channel_items_pkey PRIMARY KEY (channel_id, title_id);

ALTER TABLE ONLY group_channels
    ADD CONSTRAINT group_channels_group_id_name_key UNIQUE (group_id, name);

ALTER TABLE ONLY group_channels
    ADD CONSTRAINT group_channels_pkey PRIMARY KEY (id);

ALTER TABLE ONLY group_invites
    ADD CONSTRAINT group_invites_group_id_invitee_id_key UNIQUE (group_id, invitee_id);

ALTER TABLE ONLY group_invites
    ADD CONSTRAINT group_invites_pkey PRIMARY KEY (id);

ALTER TABLE ONLY group_members
    ADD CONSTRAINT group_members_pkey PRIMARY KEY (group_id, user_id);

ALTER TABLE ONLY group_messages
    ADD CONSTRAINT group_messages_author_id_client_nonce_key UNIQUE (author_id, client_nonce);

ALTER TABLE ONLY group_messages
    ADD CONSTRAINT group_messages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY group_read_state
    ADD CONSTRAINT group_read_state_pkey PRIMARY KEY (user_id, channel_id);

ALTER TABLE ONLY groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);

ALTER TABLE ONLY import_jobs
    ADD CONSTRAINT import_jobs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY import_listens
    ADD CONSTRAINT import_listens_pkey PRIMARY KEY (job_id, idx);

ALTER TABLE ONLY import_rows
    ADD CONSTRAINT import_rows_pkey PRIMARY KEY (job_id, idx);

ALTER TABLE ONLY library_items
    ADD CONSTRAINT library_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY library_items
    ADD CONSTRAINT library_items_user_id_title_id_key UNIQUE (user_id, title_id);

ALTER TABLE ONLY library_tombstones
    ADD CONSTRAINT library_tombstones_pkey PRIMARY KEY (user_id, library_item_id);

ALTER TABLE ONLY list_items
    ADD CONSTRAINT list_items_list_id_title_id_key UNIQUE (list_id, title_id);

ALTER TABLE ONLY list_items
    ADD CONSTRAINT list_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY listens
    ADD CONSTRAINT listens_pkey PRIMARY KEY (id);

ALTER TABLE ONLY listens
    ADD CONSTRAINT listens_user_id_track_key_listened_at_key UNIQUE (user_id, track_key, listened_at);

ALTER TABLE ONLY lists
    ADD CONSTRAINT lists_pkey PRIMARY KEY (id);

ALTER TABLE ONLY live_activity_states
    ADD CONSTRAINT live_activity_states_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY live_activity_tokens
    ADD CONSTRAINT live_activity_tokens_pkey PRIMARY KEY (token);

ALTER TABLE ONLY live_plays
    ADD CONSTRAINT live_plays_id_key UNIQUE (id);

ALTER TABLE ONLY live_plays
    ADD CONSTRAINT live_plays_pkey PRIMARY KEY (user_id, kind, agent_token_id);

ALTER TABLE ONLY magic_links
    ADD CONSTRAINT magic_links_pkey PRIMARY KEY (id);

ALTER TABLE ONLY magic_links
    ADD CONSTRAINT magic_links_token_hash_key UNIQUE (token_hash);

ALTER TABLE ONLY mal_auth_requests
    ADD CONSTRAINT mal_auth_requests_pkey PRIMARY KEY (state_hash);

ALTER TABLE ONLY mal_connections
    ADD CONSTRAINT mal_connections_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY mal_entry_states
    ADD CONSTRAINT mal_entry_states_pkey PRIMARY KEY (user_id, mal_id);

ALTER TABLE ONLY music_artists
    ADD CONSTRAINT music_artists_pkey PRIMARY KEY (musicbrainz);

ALTER TABLE ONLY music_lookups
    ADD CONSTRAINT music_lookups_pkey PRIMARY KEY (track_key, album_key);

ALTER TABLE ONLY notification_settings
    ADD CONSTRAINT notification_settings_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY notifications_sent
    ADD CONSTRAINT notifications_sent_pkey PRIMARY KEY (user_id, title_id, season, episode);

ALTER TABLE ONLY oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);

ALTER TABLE ONLY oauth_codes
    ADD CONSTRAINT oauth_codes_pkey PRIMARY KEY (code_hash);

ALTER TABLE ONLY oauth_refresh_tokens
    ADD CONSTRAINT oauth_refresh_tokens_pkey PRIMARY KEY (token_hash);

ALTER TABLE ONLY oauth_requests
    ADD CONSTRAINT oauth_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY points_events
    ADD CONSTRAINT points_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY points_events
    ADD CONSTRAINT points_events_user_id_dedupe_key_key UNIQUE (user_id, dedupe_key);

ALTER TABLE ONLY profiles
    ADD CONSTRAINT profiles_handle_key UNIQUE (handle);

ALTER TABLE ONLY profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY saved_queries
    ADD CONSTRAINT saved_queries_pkey PRIMARY KEY (id);

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_token_hash_key UNIQUE (token_hash);

ALTER TABLE ONLY shares
    ADD CONSTRAINT shares_pkey PRIMARY KEY (code);

ALTER TABLE ONLY show_episodes
    ADD CONSTRAINT show_episodes_pkey PRIMARY KEY (id);

ALTER TABLE ONLY show_episodes
    ADD CONSTRAINT show_episodes_title_id_season_episode_key UNIQUE (title_id, season, episode);

ALTER TABLE ONLY social_blocks
    ADD CONSTRAINT social_blocks_pkey PRIMARY KEY (blocker_id, blocked_id);

ALTER TABLE ONLY social_friend_requests
    ADD CONSTRAINT social_friend_requests_from_user_id_to_user_id_key UNIQUE (from_user_id, to_user_id);

ALTER TABLE ONLY social_friend_requests
    ADD CONSTRAINT social_friend_requests_pkey PRIMARY KEY (id);

ALTER TABLE ONLY social_friendships
    ADD CONSTRAINT social_friendships_pkey PRIMARY KEY (user_low, user_high);

ALTER TABLE ONLY social_invites
    ADD CONSTRAINT social_invites_code_key UNIQUE (code);

ALTER TABLE ONLY social_invites
    ADD CONSTRAINT social_invites_pkey PRIMARY KEY (id);

ALTER TABLE ONLY social_reactions
    ADD CONSTRAINT social_reactions_pkey PRIMARY KEY (user_id, owner_id, title_id, day);

ALTER TABLE ONLY social_recommendations
    ADD CONSTRAINT social_recommendations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY social_reports
    ADD CONSTRAINT social_reports_pkey PRIMARY KEY (id);

ALTER TABLE ONLY social_settings
    ADD CONSTRAINT social_settings_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY sport_follows
    ADD CONSTRAINT sport_follows_pkey PRIMARY KEY (user_id, kind, provider_id);

ALTER TABLE ONLY sport_settings
    ADD CONSTRAINT sport_settings_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY stremio_link_requests
    ADD CONSTRAINT stremio_link_requests_pkey PRIMARY KEY (code);

ALTER TABLE ONLY titles
    ADD CONSTRAINT titles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY tonight_feedback
    ADD CONSTRAINT tonight_feedback_pkey PRIMARY KEY (id);

ALTER TABLE ONLY tonight_picks
    ADD CONSTRAINT tonight_picks_pkey PRIMARY KEY (user_id, day, library_item_id);

ALTER TABLE ONLY trakt_auth_requests
    ADD CONSTRAINT trakt_auth_requests_pkey PRIMARY KEY (state_hash);

ALTER TABLE ONLY trakt_connections
    ADD CONSTRAINT trakt_connections_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY user_badges
    ADD CONSTRAINT user_badges_pkey PRIMARY KEY (id);

ALTER TABLE ONLY user_badges
    ADD CONSTRAINT user_badges_user_id_badge_tier_key UNIQUE (user_id, badge, tier);

ALTER TABLE ONLY user_progress
    ADD CONSTRAINT user_progress_pkey PRIMARY KEY (user_id);

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

ALTER TABLE ONLY watch_events
    ADD CONSTRAINT watch_events_pkey PRIMARY KEY (id);

ALTER TABLE ONLY watch_ready
    ADD CONSTRAINT watch_ready_pkey PRIMARY KEY (session_id, user_id);

ALTER TABLE ONLY watch_sessions
    ADD CONSTRAINT watch_sessions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY web_push_subscriptions
    ADD CONSTRAINT web_push_subscriptions_pkey PRIMARY KEY (endpoint);

CREATE INDEX actions_agent_token ON actions USING btree (agent_token_id) WHERE (agent_token_id IS NOT NULL);

CREATE INDEX actions_user_created ON actions USING btree (user_id, created_at DESC);

CREATE INDEX agent_plans_pending_token ON agent_plans USING btree (agent_token_id) WHERE (status = 'pending'::text);

CREATE INDEX agent_plans_token ON agent_plans USING btree (agent_token_id) WHERE (agent_token_id IS NOT NULL);

CREATE INDEX agent_plans_user ON agent_plans USING btree (user_id, created_at DESC);

CREATE INDEX agent_replies_channel ON agent_replies USING btree (channel_id);

CREATE INDEX agent_replies_group ON agent_replies USING btree (group_id, created_at);

CREATE INDEX agent_replies_queue ON agent_replies USING btree (state, created_at);

CREATE INDEX agent_replies_tagger ON agent_replies USING btree (tagger_id, created_at);

CREATE INDEX agent_tokens_user ON agent_tokens USING btree (user_id) WHERE (revoked_at IS NULL);

CREATE INDEX album_artists_artist ON album_artists USING btree (artist);

CREATE INDEX anime_mappings_mal ON anime_mappings USING btree (mal) WHERE (mal IS NOT NULL);

CREATE INDEX anime_mappings_tmdb ON anime_mappings USING btree (tmdb) WHERE (tmdb IS NOT NULL);

CREATE INDEX apns_devices_user ON apns_devices USING btree (user_id);

CREATE INDEX auth_identities_user_id ON auth_identities USING btree (user_id);

CREATE INDEX board_comments_post ON board_comments USING btree (post_id, created_at, id);

CREATE INDEX board_comments_reply_to ON board_comments USING btree (reply_to) WHERE (reply_to IS NOT NULL);

CREATE INDEX board_comments_user ON board_comments USING btree (user_id) WHERE (user_id IS NOT NULL);

CREATE INDEX board_posts_author ON board_posts USING btree (user_id, created_at DESC);

CREATE INDEX board_posts_feed ON board_posts USING btree (created_at DESC, id DESC) WHERE (deleted_at IS NULL);

CREATE INDEX board_posts_title ON board_posts USING btree (title_id) WHERE (title_id IS NOT NULL);

CREATE INDEX board_upvotes_user ON board_upvotes USING btree (user_id);

CREATE INDEX capture_inputs_created ON capture_inputs USING btree (created_at);

CREATE INDEX entitlements_user ON entitlements USING btree (user_id);

CREATE INDEX episode_progress_item_watched ON episode_progress USING btree (library_item_id, watched_at);

CREATE INDEX favorites_title ON favorites USING btree (title_id);

CREATE UNIQUE INDEX group_channels_one_default ON group_channels USING btree (group_id) WHERE is_default;

CREATE INDEX group_invites_invitee ON group_invites USING btree (invitee_id);

CREATE INDEX group_invites_inviter ON group_invites USING btree (inviter_id);

CREATE UNIQUE INDEX group_members_one_owner ON group_members USING btree (group_id) WHERE (role = 'owner'::text);

CREATE INDEX group_members_user ON group_members USING btree (user_id);

CREATE INDEX group_messages_author ON group_messages USING btree (author_id);

CREATE INDEX group_messages_channel ON group_messages USING btree (channel_id, created_at DESC, id DESC);

CREATE INDEX group_messages_reply_to ON group_messages USING btree (reply_to) WHERE (reply_to IS NOT NULL);

CREATE INDEX import_jobs_capture ON import_jobs USING btree (user_id, created_at) WHERE (source = 'capture'::text);

CREATE INDEX import_jobs_claim ON import_jobs USING btree (state, locked_until, created_at);

CREATE INDEX import_jobs_user_created ON import_jobs USING btree (user_id, created_at DESC);

CREATE INDEX library_items_title ON library_items USING btree (title_id);

CREATE INDEX library_items_user_updated ON library_items USING btree (user_id, updated_at, id);

CREATE INDEX library_tombstones_user_deleted ON library_tombstones USING btree (user_id, deleted_at);

CREATE INDEX list_items_title ON list_items USING btree (title_id);

CREATE INDEX listens_import_job ON listens USING btree (import_job_id) WHERE (import_job_id IS NOT NULL);

CREATE INDEX listens_unresolved ON listens USING btree (track_key) WHERE (release_group_mbid IS NULL);

CREATE INDEX listens_user_time ON listens USING btree (user_id, listened_at DESC);

CREATE INDEX lists_user_id ON lists USING btree (user_id);

CREATE INDEX live_activity_states_due ON live_activity_states USING btree (next_check_at) WHERE (next_check_at IS NOT NULL);

CREATE INDEX live_activity_tokens_user ON live_activity_tokens USING btree (user_id, kind);

CREATE INDEX magic_links_email ON magic_links USING btree (email);

CREATE INDEX oauth_codes_token ON oauth_codes USING btree (agent_token_id) WHERE (agent_token_id IS NOT NULL);

CREATE INDEX oauth_codes_user ON oauth_codes USING btree (user_id);

CREATE INDEX oauth_refresh_tokens_token ON oauth_refresh_tokens USING btree (agent_token_id);

CREATE INDEX points_events_day ON points_events USING btree (user_id, local_date);

CREATE INDEX points_events_reverses ON points_events USING btree (reverses) WHERE (reverses IS NOT NULL);

CREATE INDEX points_events_root ON points_events USING btree (user_id, dedupe_root, seq DESC);

CREATE INDEX saved_queries_user ON saved_queries USING btree (user_id, created_at);

CREATE INDEX sessions_user_id ON sessions USING btree (user_id);

CREATE INDEX shares_sender ON shares USING btree (sender_id, created_at DESC);

CREATE INDEX shares_title ON shares USING btree (title_id);

CREATE INDEX show_episodes_airs_at ON show_episodes USING btree (airs_at) WHERE (airs_at IS NOT NULL);

CREATE INDEX social_blocks_blocked ON social_blocks USING btree (blocked_id);

CREATE INDEX social_friend_requests_to ON social_friend_requests USING btree (to_user_id);

CREATE INDEX social_friendships_high ON social_friendships USING btree (user_high);

CREATE INDEX social_invites_inviter ON social_invites USING btree (inviter_id, created_at DESC);

CREATE INDEX social_reactions_row ON social_reactions USING btree (owner_id, title_id, day);

CREATE INDEX social_recommendations_inbox ON social_recommendations USING btree (to_user_id, created_at DESC);

CREATE UNIQUE INDEX social_recommendations_open ON social_recommendations USING btree (from_user_id, to_user_id, title_id) WHERE ((added_at IS NULL) AND (dismissed_at IS NULL));

CREATE UNIQUE INDEX titles_anidb_key ON titles USING btree (anidb) WHERE (anidb IS NOT NULL);

CREATE UNIQUE INDEX titles_anilist_key ON titles USING btree (anilist) WHERE (anilist IS NOT NULL);

CREATE UNIQUE INDEX titles_imdb_key ON titles USING btree (imdb) WHERE (imdb IS NOT NULL);

CREATE UNIQUE INDEX titles_isbn_key ON titles USING btree (isbn) WHERE (isbn IS NOT NULL);

CREATE UNIQUE INDEX titles_mal_key ON titles USING btree (mal) WHERE ((mal IS NOT NULL) AND (type <> 'manga'::text));

CREATE UNIQUE INDEX titles_manga_mal_key ON titles USING btree (mal) WHERE ((mal IS NOT NULL) AND (type = 'manga'::text));

CREATE UNIQUE INDEX titles_musicbrainz_key ON titles USING btree (musicbrainz) WHERE (musicbrainz IS NOT NULL);

CREATE UNIQUE INDEX titles_open_library_key ON titles USING btree (open_library) WHERE (open_library IS NOT NULL);

CREATE UNIQUE INDEX titles_tvdb_key ON titles USING btree (tvdb) WHERE (tvdb IS NOT NULL);

CREATE UNIQUE INDEX titles_type_tmdb_key ON titles USING btree (type, tmdb) WHERE (tmdb IS NOT NULL);

CREATE UNIQUE INDEX titles_type_trakt_key ON titles USING btree (type, trakt) WHERE (trakt IS NOT NULL);

CREATE INDEX tonight_feedback_user ON tonight_feedback USING btree (user_id, created_at);

CREATE INDEX tonight_picks_item ON tonight_picks USING btree (library_item_id, served_at);

CREATE INDEX user_badges_unseen ON user_badges USING btree (user_id) WHERE (seen_at IS NULL);

CREATE INDEX user_progress_dirty ON user_progress USING btree (dirty_at) WHERE (dirty_at IS NOT NULL);

CREATE INDEX watch_events_agent_token ON watch_events USING btree (agent_token_id) WHERE (agent_token_id IS NOT NULL);

CREATE UNIQUE INDEX watch_events_open ON watch_events USING btree (user_id, source, external_ref) WHERE (stopped_at IS NULL);

CREATE INDEX watch_events_stopped ON watch_events USING btree (user_id, source, external_ref, stopped_at);

CREATE INDEX watch_events_user ON watch_events USING btree (user_id, updated_at DESC);

CREATE INDEX watch_ready_user ON watch_ready USING btree (user_id);

CREATE INDEX watch_sessions_channel ON watch_sessions USING btree (channel_id, created_at DESC);

CREATE UNIQUE INDEX watch_sessions_one_open ON watch_sessions USING btree (channel_id) WHERE (ended_at IS NULL);

CREATE INDEX web_push_subscriptions_user ON web_push_subscriptions USING btree (user_id);

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE SET NULL;

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_undo_of_fkey FOREIGN KEY (undo_of) REFERENCES actions(id) ON DELETE SET NULL;

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_plans
    ADD CONSTRAINT agent_plans_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE SET NULL;

ALTER TABLE ONLY agent_plans
    ADD CONSTRAINT agent_plans_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE SET NULL;

ALTER TABLE ONLY agent_plans
    ADD CONSTRAINT agent_plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_replies
    ADD CONSTRAINT agent_replies_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES group_channels(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_replies
    ADD CONSTRAINT agent_replies_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_replies
    ADD CONSTRAINT agent_replies_message_id_fkey FOREIGN KEY (message_id) REFERENCES group_messages(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_replies
    ADD CONSTRAINT agent_replies_tagger_id_fkey FOREIGN KEY (tagger_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_tokens
    ADD CONSTRAINT agent_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY agent_usage
    ADD CONSTRAINT agent_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY album_artists
    ADD CONSTRAINT album_artists_artist_fkey FOREIGN KEY (artist) REFERENCES music_artists(musicbrainz) ON DELETE CASCADE;

ALTER TABLE ONLY album_artists
    ADD CONSTRAINT album_artists_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE CASCADE;

ALTER TABLE ONLY album_tracks
    ADD CONSTRAINT album_tracks_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE CASCADE;

ALTER TABLE ONLY apns_devices
    ADD CONSTRAINT apns_devices_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY auth_identities
    ADD CONSTRAINT auth_identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY avatars
    ADD CONSTRAINT avatars_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY board_comments
    ADD CONSTRAINT board_comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES board_posts(id) ON DELETE CASCADE;

ALTER TABLE ONLY board_comments
    ADD CONSTRAINT board_comments_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES board_comments(id) ON DELETE SET NULL;

ALTER TABLE ONLY board_comments
    ADD CONSTRAINT board_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY board_posts
    ADD CONSTRAINT board_posts_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY board_posts
    ADD CONSTRAINT board_posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY board_upvotes
    ADD CONSTRAINT board_upvotes_post_id_fkey FOREIGN KEY (post_id) REFERENCES board_posts(id) ON DELETE CASCADE;

ALTER TABLE ONLY board_upvotes
    ADD CONSTRAINT board_upvotes_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY capture_inputs
    ADD CONSTRAINT capture_inputs_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY check_ins
    ADD CONSTRAINT check_ins_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY concert_places
    ADD CONSTRAINT concert_places_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY entitlements
    ADD CONSTRAINT entitlements_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY episode_progress
    ADD CONSTRAINT episode_progress_library_item_id_fkey FOREIGN KEY (library_item_id) REFERENCES library_items(id) ON DELETE CASCADE;

ALTER TABLE ONLY favorites
    ADD CONSTRAINT favorites_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY favorites
    ADD CONSTRAINT favorites_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_channel_items
    ADD CONSTRAINT group_channel_items_added_by_fkey FOREIGN KEY (added_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE ONLY group_channel_items
    ADD CONSTRAINT group_channel_items_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES group_channels(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_channel_items
    ADD CONSTRAINT group_channel_items_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY group_channels
    ADD CONSTRAINT group_channels_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_channels
    ADD CONSTRAINT group_channels_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY group_invites
    ADD CONSTRAINT group_invites_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_invites
    ADD CONSTRAINT group_invites_invitee_id_fkey FOREIGN KEY (invitee_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_invites
    ADD CONSTRAINT group_invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_members
    ADD CONSTRAINT group_members_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_members
    ADD CONSTRAINT group_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_messages
    ADD CONSTRAINT group_messages_author_id_fkey FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE ONLY group_messages
    ADD CONSTRAINT group_messages_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES group_channels(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_messages
    ADD CONSTRAINT group_messages_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES group_messages(id) ON DELETE SET NULL;

ALTER TABLE ONLY group_read_state
    ADD CONSTRAINT group_read_state_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES group_channels(id) ON DELETE CASCADE;

ALTER TABLE ONLY group_read_state
    ADD CONSTRAINT group_read_state_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY import_jobs
    ADD CONSTRAINT import_jobs_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE SET NULL;

ALTER TABLE ONLY import_jobs
    ADD CONSTRAINT import_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY import_listens
    ADD CONSTRAINT import_listens_job_id_fkey FOREIGN KEY (job_id) REFERENCES import_jobs(id) ON DELETE CASCADE;

ALTER TABLE ONLY import_rows
    ADD CONSTRAINT import_rows_job_id_fkey FOREIGN KEY (job_id) REFERENCES import_jobs(id) ON DELETE CASCADE;

ALTER TABLE ONLY import_rows
    ADD CONSTRAINT import_rows_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE SET NULL;

ALTER TABLE ONLY library_items
    ADD CONSTRAINT library_items_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY library_items
    ADD CONSTRAINT library_items_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY library_tombstones
    ADD CONSTRAINT library_tombstones_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY list_items
    ADD CONSTRAINT list_items_list_id_fkey FOREIGN KEY (list_id) REFERENCES lists(id) ON DELETE CASCADE;

ALTER TABLE ONLY list_items
    ADD CONSTRAINT list_items_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY listens
    ADD CONSTRAINT listens_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE SET NULL;

ALTER TABLE ONLY listens
    ADD CONSTRAINT listens_import_job_id_fkey FOREIGN KEY (import_job_id) REFERENCES import_jobs(id) ON DELETE SET NULL;

ALTER TABLE ONLY listens
    ADD CONSTRAINT listens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY lists
    ADD CONSTRAINT lists_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY live_activity_states
    ADD CONSTRAINT live_activity_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY live_activity_tokens
    ADD CONSTRAINT live_activity_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY live_plays
    ADD CONSTRAINT live_plays_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE CASCADE;

ALTER TABLE ONLY live_plays
    ADD CONSTRAINT live_plays_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY mal_auth_requests
    ADD CONSTRAINT mal_auth_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY mal_connections
    ADD CONSTRAINT mal_connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY mal_entry_states
    ADD CONSTRAINT mal_entry_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY notification_settings
    ADD CONSTRAINT notification_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY notifications_sent
    ADD CONSTRAINT notifications_sent_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE CASCADE;

ALTER TABLE ONLY notifications_sent
    ADD CONSTRAINT notifications_sent_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY oauth_codes
    ADD CONSTRAINT oauth_codes_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE SET NULL;

ALTER TABLE ONLY oauth_codes
    ADD CONSTRAINT oauth_codes_client_id_fkey FOREIGN KEY (client_id) REFERENCES oauth_clients(id) ON DELETE CASCADE;

ALTER TABLE ONLY oauth_codes
    ADD CONSTRAINT oauth_codes_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY oauth_refresh_tokens
    ADD CONSTRAINT oauth_refresh_tokens_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE CASCADE;

ALTER TABLE ONLY oauth_requests
    ADD CONSTRAINT oauth_requests_client_id_fkey FOREIGN KEY (client_id) REFERENCES oauth_clients(id) ON DELETE CASCADE;

ALTER TABLE ONLY points_events
    ADD CONSTRAINT points_events_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE SET NULL;

ALTER TABLE ONLY points_events
    ADD CONSTRAINT points_events_reverses_fkey FOREIGN KEY (reverses) REFERENCES points_events(id) ON DELETE CASCADE;

ALTER TABLE ONLY points_events
    ADD CONSTRAINT points_events_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE SET NULL;

ALTER TABLE ONLY points_events
    ADD CONSTRAINT points_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY saved_queries
    ADD CONSTRAINT saved_queries_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY shares
    ADD CONSTRAINT shares_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE ONLY shares
    ADD CONSTRAINT shares_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY show_episodes
    ADD CONSTRAINT show_episodes_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_blocks
    ADD CONSTRAINT social_blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_blocks
    ADD CONSTRAINT social_blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_friend_requests
    ADD CONSTRAINT social_friend_requests_from_user_id_fkey FOREIGN KEY (from_user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_friend_requests
    ADD CONSTRAINT social_friend_requests_to_user_id_fkey FOREIGN KEY (to_user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_friendships
    ADD CONSTRAINT social_friendships_user_high_fkey FOREIGN KEY (user_high) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_friendships
    ADD CONSTRAINT social_friendships_user_low_fkey FOREIGN KEY (user_low) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_invites
    ADD CONSTRAINT social_invites_inviter_id_fkey FOREIGN KEY (inviter_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_invites
    ADD CONSTRAINT social_invites_redeemed_by_fkey FOREIGN KEY (redeemed_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE ONLY social_invites
    ADD CONSTRAINT social_invites_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY social_reactions
    ADD CONSTRAINT social_reactions_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_reactions
    ADD CONSTRAINT social_reactions_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_reactions
    ADD CONSTRAINT social_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_recommendations
    ADD CONSTRAINT social_recommendations_from_user_id_fkey FOREIGN KEY (from_user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_recommendations
    ADD CONSTRAINT social_recommendations_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_recommendations
    ADD CONSTRAINT social_recommendations_to_user_id_fkey FOREIGN KEY (to_user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_reports
    ADD CONSTRAINT social_reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY social_reports
    ADD CONSTRAINT social_reports_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE ONLY social_settings
    ADD CONSTRAINT social_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY sport_follows
    ADD CONSTRAINT sport_follows_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY sport_settings
    ADD CONSTRAINT sport_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY stremio_link_requests
    ADD CONSTRAINT stremio_link_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY tonight_feedback
    ADD CONSTRAINT tonight_feedback_library_item_id_fkey FOREIGN KEY (library_item_id) REFERENCES library_items(id) ON DELETE CASCADE;

ALTER TABLE ONLY tonight_feedback
    ADD CONSTRAINT tonight_feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY tonight_picks
    ADD CONSTRAINT tonight_picks_library_item_id_fkey FOREIGN KEY (library_item_id) REFERENCES library_items(id) ON DELETE CASCADE;

ALTER TABLE ONLY tonight_picks
    ADD CONSTRAINT tonight_picks_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY trakt_auth_requests
    ADD CONSTRAINT trakt_auth_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY trakt_connections
    ADD CONSTRAINT trakt_connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY user_badges
    ADD CONSTRAINT user_badges_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE SET NULL;

ALTER TABLE ONLY user_badges
    ADD CONSTRAINT user_badges_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY user_progress
    ADD CONSTRAINT user_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY watch_events
    ADD CONSTRAINT watch_events_agent_token_id_fkey FOREIGN KEY (agent_token_id) REFERENCES agent_tokens(id) ON DELETE SET NULL;

ALTER TABLE ONLY watch_events
    ADD CONSTRAINT watch_events_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE SET NULL;

ALTER TABLE ONLY watch_events
    ADD CONSTRAINT watch_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY watch_ready
    ADD CONSTRAINT watch_ready_session_id_fkey FOREIGN KEY (session_id) REFERENCES watch_sessions(id) ON DELETE CASCADE;

ALTER TABLE ONLY watch_ready
    ADD CONSTRAINT watch_ready_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE ONLY watch_sessions
    ADD CONSTRAINT watch_sessions_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES group_channels(id) ON DELETE CASCADE;

ALTER TABLE ONLY watch_sessions
    ADD CONSTRAINT watch_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE ONLY watch_sessions
    ADD CONSTRAINT watch_sessions_title_id_fkey FOREIGN KEY (title_id) REFERENCES titles(id) ON DELETE RESTRICT;

ALTER TABLE ONLY web_push_subscriptions
    ADD CONSTRAINT web_push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
