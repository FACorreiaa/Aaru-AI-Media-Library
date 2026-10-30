package scrobble

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/push"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store is PostgresWatchEventStore: watch events, plays, Live Activity tokens and the activity's state.
type Store struct {
	Q *sqlc.Queries
}

// NewStore builds the store over the pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{Q: sqlc.New(pool)} }

func ts(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: true} }

func i32(n int) int32 { return int32(min(max(n, math.MinInt32), math.MaxInt32)) } //nolint:gosec // clamped

// Record opens or updates the session for this user, source and item, and returns it.
func (s *Store) Record(ctx context.Context, r Report, titleID *uuid.UUID, user uuid.UUID, agentTokenID *uuid.UUID, now time.Time) (Session, error) {
	var season, episode *int32
	if r.Episode != nil {
		sv, ev := i32(r.Episode.Season), i32(r.Episode.Episode)
		season, episode = &sv, &ev
	}
	row, err := s.Q.RecordWatchEvent(ctx, sqlc.RecordWatchEventParams{
		ID: uuid.New(), UserID: user, AgentTokenID: agentTokenID, Source: string(r.Source), ExternalRef: r.ExternalRef,
		TitleID: titleID, Season: season, Episode: episode, State: r.Action.State(), PositionMs: r.PositionMs,
		DurationMs: r.DurationMs, Now: ts(now),
	})
	if err != nil {
		return Session{}, fmt.Errorf("record watch event: %w", err)
	}
	return Session{ID: row.ID, TitleID: row.TitleID, PositionMs: row.PositionMs, DurationMs: row.DurationMs}, nil
}

// Close closes a session.
func (s *Store) Close(ctx context.Context, id uuid.UUID, at time.Time) error {
	if err := s.Q.CloseWatchEvent(ctx, sqlc.CloseWatchEventParams{At: ts(at), ID: id}); err != nil {
		return fmt.Errorf("close watch event: %w", err)
	}
	return nil
}

// StoppedRecently is whether a session for this item was closed since since: a second `stop` is a repeat.
func (s *Store) StoppedRecently(ctx context.Context, user uuid.UUID, source WatchSource, externalRef string, since time.Time) (bool, error) {
	found, err := s.Q.StoppedRecently(ctx, sqlc.StoppedRecentlyParams{
		UserID: user, Source: string(source), ExternalRef: externalRef, Since: ts(since),
	})
	if err != nil {
		return false, fmt.Errorf("stopped recently: %w", err)
	}
	return found, nil
}

// OpenSessions is the user's open, matched sessions, newest report first; only source's when given.
func (s *Store) OpenSessions(ctx context.Context, user uuid.UUID, source *WatchSource, limit int) ([]OpenSession, error) {
	var src *string
	if source != nil {
		v := string(*source)
		src = &v
	}
	rows, err := s.Q.OpenWatchEvents(ctx, sqlc.OpenWatchEventsParams{UserID: user, Source: src, MaxRows: i32(limit)})
	if err != nil {
		return nil, fmt.Errorf("open watch events: %w", err)
	}
	out := make([]OpenSession, 0, len(rows))
	for _, r := range rows {
		source, ok := ParseWatchSource(r.Source)
		state := State(r.State)
		if !ok || (state != Playing && state != Paused) || r.TitleID == nil {
			continue
		}
		var episode *core.EpisodeKey
		if r.Season != nil && r.Episode != nil {
			if k, err := core.NewEpisodeKey(int(*r.Season), int(*r.Episode)); err == nil {
				episode = &k
			}
		}
		runtime := r.EpisodeRuntime
		if runtime == nil {
			runtime = r.TitleRuntime
		}
		var minutes *int
		if runtime != nil {
			m := int(*runtime)
			minutes = &m
		}
		out = append(out, OpenSession{
			ID: r.ID, Source: source, ExternalRef: r.ExternalRef, TitleID: *r.TitleID, LibraryItemID: r.ItemID,
			Episode: episode, EpisodeName: r.EpisodeName, RuntimeMinutes: minutes, State: state,
			PositionMs: r.PositionMs, DurationMs: r.DurationMs, UpdatedAt: r.UpdatedAt,
		})
	}
	return out, nil
}

// MARK: Live Activity tokens

// RegisterLiveActivity keeps a token; a token belongs to one user, so registering it again moves it.
func (s *Store) RegisterLiveActivity(ctx context.Context, t push.LiveActivityToken, user uuid.UUID, now time.Time) error {
	err := s.Q.RegisterLiveActivityToken(ctx, sqlc.RegisterLiveActivityTokenParams{
		Token: t.Token, UserID: user, Kind: string(t.Kind), Environment: string(t.Environment), Topic: t.Topic, Now: ts(now),
	})
	if err != nil {
		return fmt.Errorf("register live activity token: %w", err)
	}
	return nil
}

// HasLiveActivityTokens is whether the user has any token: a user with none has no activity to keep.
func (s *Store) HasLiveActivityTokens(ctx context.Context, user uuid.UUID) (bool, error) {
	found, err := s.Q.HasLiveActivityTokens(ctx, user)
	if err != nil {
		return false, fmt.Errorf("live activity tokens: %w", err)
	}
	return found, nil
}

// LiveActivityTokens is the user's push-to-start tokens (start) or running activities' tokens
// (update), one per device.
func (s *Store) LiveActivityTokens(ctx context.Context, user uuid.UUID, kind push.LiveActivityTokenKind) ([]push.LiveActivityToken, error) {
	rows, err := s.Q.LiveActivityTokens(ctx, sqlc.LiveActivityTokensParams{UserID: user, Kind: string(kind)})
	if err != nil {
		return nil, fmt.Errorf("live activity tokens: %w", err)
	}
	out := make([]push.LiveActivityToken, 0, len(rows))
	for _, r := range rows {
		env := push.Environment(r.Environment)
		k := push.LiveActivityTokenKind(r.Kind)
		if (env != push.Sandbox && env != push.Production) ||
			(k != push.LiveActivityTokenStart && k != push.LiveActivityTokenUpdate) {
			continue
		}
		out = append(out, push.LiveActivityToken{Token: r.Token, Kind: k, Environment: env, Topic: r.Topic})
	}
	return out, nil
}

// ForgetLiveActivity drops a token Apple said is dead (activity ended, app removed).
func (s *Store) ForgetLiveActivity(ctx context.Context, token string) error {
	if err := s.Q.ForgetLiveActivityToken(ctx, token); err != nil {
		return fmt.Errorf("forget live activity token: %w", err)
	}
	return nil
}

// ForgetLiveActivityUpdates drops the ended activities' tokens: they will not answer again.
func (s *Store) ForgetLiveActivityUpdates(ctx context.Context, user uuid.UUID) error {
	if err := s.Q.ForgetLiveActivityUpdates(ctx, user); err != nil {
		return fmt.Errorf("forget live activity updates: %w", err)
	}
	return nil
}

// MARK: Plays (SCR-009)

// SavePlay saves what a connection plays now, replacing its last play of that kind. The same Ref
// again keeps the row's id and start, so the activity hears no change.
func (s *Store) SavePlay(ctx context.Context, p LivePlay, user, agentTokenID uuid.UUID) error {
	err := s.Q.SaveLivePlay(ctx, sqlc.SaveLivePlayParams{
		UserID: user, AgentTokenID: agentTokenID, Kind: string(p.Kind), ID: p.ID, Source: string(p.Source), Ref: p.Ref,
		Title: p.Title, Subtitle: p.Subtitle, Service: p.Service, ArtworkUrl: p.ArtworkURL, OriginUrl: p.OriginURL,
		State: string(p.State), PositionMs: p.PositionMs, DurationMs: p.DurationMs, StartedAt: ts(p.StartedAt),
		UpdatedAt: ts(p.UpdatedAt), ExpiresAt: ts(p.ExpiresAt),
	})
	if err != nil {
		return fmt.Errorf("save live play: %w", err)
	}
	return nil
}

// RemovePlay is the connection having stopped playing that kind of thing.
func (s *Store) RemovePlay(ctx context.Context, kind PlayKind, user, agentTokenID uuid.UUID) error {
	if err := s.Q.RemoveLivePlay(ctx, sqlc.RemoveLivePlayParams{UserID: user, Kind: string(kind), AgentTokenID: agentTokenID}); err != nil {
		return fmt.Errorf("remove live play: %w", err)
	}
	return nil
}

// LivePlays is the user's plays that have not expired, newest report first. Expired ones are deleted.
func (s *Store) LivePlays(ctx context.Context, user uuid.UUID, now time.Time) ([]LivePlay, error) {
	if err := s.Q.DeleteExpiredLivePlays(ctx, sqlc.DeleteExpiredLivePlaysParams{UserID: user, Now: ts(now)}); err != nil {
		return nil, fmt.Errorf("expire live plays: %w", err)
	}
	rows, err := s.Q.LivePlays(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("live plays: %w", err)
	}
	out := make([]LivePlay, 0, len(rows))
	for _, r := range rows {
		kind, source, state := PlayKind(r.Kind), PlaySource(r.Source), State(r.State)
		if (kind != PlayTrack && kind != PlayVideo) || (source != PlayListenBrainz && source != PlayYouTube) ||
			(state != Playing && state != Paused) {
			continue
		}
		out = append(out, LivePlay{
			ID: r.ID, Kind: kind, Source: source, Ref: r.Ref, Title: r.Title, Subtitle: r.Subtitle, Service: r.Service,
			ArtworkURL: r.ArtworkUrl, OriginURL: r.OriginUrl, State: state, PositionMs: r.PositionMs,
			DurationMs: r.DurationMs, StartedAt: r.StartedAt, UpdatedAt: r.UpdatedAt, ExpiresAt: r.ExpiresAt,
		})
	}
	return out, nil
}

// MARK: The activity's state

// LiveActivityState is what the user's activity last showed; a fresh state when there is none yet.
func (s *Store) LiveActivityState(ctx context.Context, user uuid.UUID) (LiveActivityState, error) {
	if err := s.Q.EnsureLiveActivityState(ctx, user); err != nil {
		return LiveActivityState{}, fmt.Errorf("live activity state: %w", err)
	}
	row, err := s.Q.LiveActivityState(ctx, user)
	if err != nil {
		return LiveActivityState{}, fmt.Errorf("live activity state: %w", err)
	}
	state := LiveActivityState{Lingering: []Lingering{}, Version: int(row.Version), NextCheckAt: row.NextCheckAt}
	if len(row.Pushed) > 0 && string(row.Pushed) != "null" {
		var pushed core.NowPlayingActivityState
		if err := json.Unmarshal(row.Pushed, &pushed); err != nil {
			return LiveActivityState{}, fmt.Errorf("live activity state: %w", err)
		}
		state.Pushed = &pushed
	}
	if err := json.Unmarshal(row.Lingering, &state.Lingering); err != nil {
		return LiveActivityState{}, fmt.Errorf("live activity state: %w", err)
	}
	return state, nil
}

// SaveLiveActivityState saves state if no one saved since it was read (its Version). False when someone did.
func (s *Store) SaveLiveActivityState(ctx context.Context, state LiveActivityState, user uuid.UUID) (bool, error) {
	var pushed json.RawMessage
	if state.Pushed != nil {
		data, err := json.Marshal(normalized(*state.Pushed))
		if err != nil {
			return false, err
		}
		pushed = data
	}
	lingering := state.Lingering
	if lingering == nil {
		lingering = []Lingering{}
	}
	data, err := json.Marshal(lingering)
	if err != nil {
		return false, err
	}
	var next pgtype.Timestamptz
	if state.NextCheckAt != nil {
		next = ts(*state.NextCheckAt)
	}
	n, err := s.Q.SaveLiveActivityState(ctx, sqlc.SaveLiveActivityStateParams{
		Pushed: pushed, Lingering: data, NextCheckAt: next, UserID: user, Version: i32(state.Version),
	})
	if err != nil {
		return false, fmt.Errorf("save live activity state: %w", err)
	}
	return n > 0, nil
}

// ScheduleLiveActivityCheck has the sweep look at the user again at at, unless it already will sooner.
func (s *Store) ScheduleLiveActivityCheck(ctx context.Context, user uuid.UUID, at time.Time) error {
	if err := s.Q.ScheduleLiveActivityCheck(ctx, sqlc.ScheduleLiveActivityCheckParams{At: ts(at), UserID: user}); err != nil {
		return fmt.Errorf("schedule live activity check: %w", err)
	}
	return nil
}

// ClaimDueLiveActivityChecks claims the users whose check is due, so one sweep alone looks at each.
func (s *Store) ClaimDueLiveActivityChecks(ctx context.Context, now time.Time, limit int) ([]uuid.UUID, error) {
	ids, err := s.Q.ClaimDueLiveActivityChecks(ctx, sqlc.ClaimDueLiveActivityChecksParams{Now: ts(now), MaxRows: i32(limit)})
	if err != nil {
		return nil, fmt.Errorf("claim live activity checks: %w", err)
	}
	return ids, nil
}

// normalized never encodes items as null: ActivityKit decodes an array.
func normalized(s core.NowPlayingActivityState) core.NowPlayingActivityState {
	if s.Items == nil {
		s.Items = []core.NowPlayingActivityItem{}
	}
	return s
}
