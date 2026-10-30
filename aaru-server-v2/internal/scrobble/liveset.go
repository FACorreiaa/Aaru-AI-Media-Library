package scrobble

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/music"
	"context"
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// MARK: Now playing (SCR-008): the newest open session that is still believable. Nothing is swept:
// a session a player never stopped simply stops counting.

const (
	// PlayingGrace is the rule — a playing session lasts until its end plus this, since the player may report late.
	PlayingGrace = 10 * time.Minute
	// UnknownDurationLimit is the rule — a playing session with no known duration lasts this long from its last report.
	UnknownDurationLimit = 3 * time.Hour
	// PausedLimit is the rule — a paused session lasts this long from the pause.
	PausedLimit = 30 * time.Minute
)

// NowPlaying is what a player is playing for the user right now: one session and its title.
type NowPlaying struct {
	Session OpenSession
	Title   core.Title
}

func ms(n int64) time.Duration { return time.Duration(n) * time.Millisecond }

// LiveUntil is when session stops counting. Stremio sends no heartbeat, so a playing session is
// assumed to keep playing from its last report.
func LiveUntil(s OpenSession) time.Time {
	if s.State == Paused {
		return s.UpdatedAt.Add(PausedLimit)
	}
	duration := s.KnownDurationMs()
	if duration <= 0 {
		return s.UpdatedAt.Add(UnknownDurationLimit)
	}
	return s.UpdatedAt.Add(ms(max(0, duration-s.PositionMs)) + PlayingGrace)
}

// IsLive is whether session still counts at now.
func IsLive(s OpenSession, now time.Time) bool { return !now.After(LiveUntil(s)) }

// Pick is the first live session of sessions (newest first).
func Pick(sessions []OpenSession, now time.Time) *OpenSession {
	for i := range sessions {
		if IsLive(sessions[i], now) {
			return &sessions[i]
		}
	}
	return nil
}

// MARK: Plays (SCR-009)

const (
	// TrackGrace is the rule — past its end by this, a track stops counting: the scrobbler sends no stop.
	TrackGrace = 2 * time.Minute
	// UnknownTrackLimit is the rule — a track with no length counts this long.
	UnknownTrackLimit = 10 * time.Minute
	// VideoHeartbeat is the rule — a playing video counts this long past its last report, at most: the extension
	// reports every few seconds, so a closed tab is gone soon after.
	VideoHeartbeat = 5 * time.Minute
	// VideoGrace is added past a video's end or heartbeat before it stops counting.
	VideoGrace = 2 * time.Minute
	// MaxText cuts text the activity shows: the whole push must stay under 4 KB.
	MaxText = 80
)

// Cut is text cut to MaxText characters.
func Cut(text string) string {
	if utf8.RuneCountInString(text) <= MaxText {
		return text
	}
	i := 0
	for pos := range text {
		if i == MaxText {
			return text[:pos]
		}
		i++
	}
	return text
}

func cutPtr(p *string) *string {
	if p == nil {
		return nil
	}
	v := Cut(*p)
	return &v
}

func str(s string) *string { return &s }

// TrackPlay is a scrobbler's `playing_now`.
func TrackPlay(l music.NewListen, now time.Time) LivePlay {
	var duration int64
	if l.DurationMs != nil {
		duration = int64(max(0, *l.DurationMs))
	}
	lasts := UnknownTrackLimit
	if duration > 0 {
		lasts = ms(duration) + TrackGrace
	}
	var artwork *string
	switch {
	case l.ReleaseGroupMBID != nil:
		artwork = str("https://coverartarchive.org/release-group/" + *l.ReleaseGroupMBID + "/front-250")
	case l.ReleaseMBID != nil:
		artwork = str("https://coverartarchive.org/release/" + *l.ReleaseMBID + "/front-250")
	}
	ref := l.TrackKey()
	if l.RecordingMBID != nil {
		ref = *l.RecordingMBID
	}
	service := l.MusicService
	if service == nil {
		service = l.Client
	}
	return LivePlay{
		ID: uuid.New(), Kind: PlayTrack, Source: PlayListenBrainz, Ref: ref, Title: Cut(l.Track),
		Subtitle: str(Cut(l.Artist)), Service: service, ArtworkURL: artwork, OriginURL: l.OriginURL, State: Playing,
		DurationMs: duration, StartedAt: now, UpdatedAt: now, ExpiresAt: now.Add(lasts),
	}
}

// VideoReport is what the browser extension reports about a YouTube video.
type VideoReport struct {
	ID         string
	Title      string
	Channel    *string
	State      State
	PositionMs int64
	DurationMs int64
}

// VideoPlay is a YouTube video the extension reports playing or paused.
func VideoPlay(r VideoReport, now time.Time) LivePlay {
	lasts := PausedLimit
	if r.State != Paused {
		lasts = min(ms(max(0, r.DurationMs-r.PositionMs)), VideoHeartbeat) + VideoGrace
	}
	return LivePlay{
		ID: uuid.New(), Kind: PlayVideo, Source: PlayYouTube, Ref: r.ID, Title: Cut(r.Title),
		Subtitle: cutPtr(r.Channel), Service: str("YouTube"),
		ArtworkURL: str("https://i.ytimg.com/vi/" + r.ID + "/mqdefault.jpg"),
		OriginURL:  str("https://www.youtube.com/watch?v=" + r.ID), State: r.State,
		PositionMs: r.PositionMs, DurationMs: r.DurationMs, StartedAt: now, UpdatedAt: now, ExpiresAt: now.Add(lasts),
	}
}

// MARK: The live set

// Entry is one thing playing now: a library episode or movie a player reports, or a play.
type Entry struct {
	// Session and Title are set for a watch event; Play otherwise.
	Session *OpenSession
	Title   *core.Title
	Play    *LivePlay
}

// UpdatedAt is when its player last reported.
func (e Entry) UpdatedAt() time.Time {
	if e.Play != nil {
		return e.Play.UpdatedAt
	}
	return e.Session.UpdatedAt
}

// LiveUntil is when it stops counting unless a player reports again.
func (e Entry) LiveUntil() time.Time {
	if e.Play != nil {
		return e.Play.ExpiresAt
	}
	return LiveUntil(*e.Session)
}

func ref(t time.Time) core.ReferenceTime { return core.ReferenceTime{Time: t} }

func refPtr(t time.Time) *core.ReferenceTime { return &core.ReferenceTime{Time: t} }

// ActivityItem is the activity's row for it.
func (e Entry) ActivityItem() core.NowPlayingActivityItem {
	if p := e.Play; p != nil {
		startedAt := p.StartedAt
		kind := core.NowPlayingTrack
		if p.Kind == PlayVideo {
			startedAt = p.UpdatedAt.Add(-ms(p.PositionMs))
			kind = core.NowPlayingVideo
		}
		item := core.NowPlayingActivityItem{
			ID: strings.ToLower(p.ID.String()), Kind: kind, Title: p.Title, Subtitle: p.Subtitle, Service: p.Service,
			StartedAt: ref(startedAt), ArtworkURL: p.ArtworkURL,
		}
		if p.DurationMs > 0 {
			item.EndsAt = refPtr(startedAt.Add(ms(p.DurationMs)))
		}
		if p.State == Paused {
			item.PausedAt = refPtr(p.UpdatedAt)
		}
		return item
	}
	s, t := e.Session, e.Title
	startedAt := s.UpdatedAt.Add(-ms(s.PositionMs))
	kind := core.NowPlayingEpisode
	if t.Type == core.MediaMovie {
		kind = core.NowPlayingMovie
	}
	item := core.NowPlayingActivityItem{
		ID: strings.ToLower(s.ID.String()), Kind: kind, Title: Cut(t.Title), Subtitle: cutPtr(EpisodeLine(*s)),
		Service: str(s.Source.Label()), StartedAt: ref(startedAt), ArtworkURL: t.PosterURL,
	}
	if d := s.KnownDurationMs(); d > 0 {
		item.EndsAt = refPtr(startedAt.Add(ms(d)))
	}
	if s.State == Paused {
		item.PausedAt = refPtr(s.UpdatedAt)
	}
	if s.LibraryItemID != nil {
		item.LibraryItemID = str(strings.ToUpper(s.LibraryItemID.String()))
	}
	if s.Episode != nil {
		season, episode := s.Episode.Season, s.Episode.Episode
		item.Season, item.Episode = &season, &episode
	}
	return item
}

// EpisodeLine is "S1 · E8 · Lanterns".
func EpisodeLine(s OpenSession) *string {
	var parts []string
	if s.Episode != nil {
		parts = append(parts, fmt.Sprintf("S%d · E%d", s.Episode.Season, s.Episode.Episode))
	}
	if s.EpisodeName != nil {
		parts = append(parts, *s.EpisodeName)
	}
	if len(parts) == 0 {
		return nil
	}
	return str(strings.Join(parts, " · "))
}

// SessionTitle is an open session and its title.
type SessionTitle struct {
	Session OpenSession
	Title   core.Title
}

// ComputeLiveSet is everything playing for a user now (SCR-009), in the activity's order: library
// episodes, movies and videos first, newest first, then tracks; at most core.NowPlayingMaxItems. A
// session must be believable (IsLive) and in the library. A track a scrobbler heard on a video already
// shown is that video again.
func ComputeLiveSet(sessions []SessionTitle, plays []LivePlay, now time.Time) []Entry {
	var first, rest []Entry
	for i := range sessions {
		s := sessions[i]
		if IsLive(s.Session, now) && s.Session.LibraryItemID != nil {
			first = append(first, Entry{Session: &s.Session, Title: &s.Title})
		}
	}
	var videos []LivePlay
	for _, p := range plays {
		if p.ExpiresAt.After(now) && p.Kind == PlayVideo {
			videos = append(videos, p)
		}
	}
	for i := range videos {
		first = append(first, Entry{Play: &videos[i]})
	}
	for i := range plays {
		p := plays[i]
		if !p.ExpiresAt.After(now) || p.Kind != PlayTrack {
			continue
		}
		heardOnVideo := false
		for _, v := range videos {
			if p.OriginURL != nil && strings.Contains(*p.OriginURL, v.Ref) {
				heardOnVideo = true
			}
		}
		if !heardOnVideo {
			rest = append(rest, Entry{Play: &p})
		}
	}
	sort.SliceStable(first, func(i, j int) bool { return first[i].UpdatedAt().After(first[j].UpdatedAt()) })
	sort.SliceStable(rest, func(i, j int) bool { return rest[i].UpdatedAt().After(rest[j].UpdatedAt()) })
	all := append(first, rest...)
	if len(all) > core.NowPlayingMaxItems {
		all = all[:core.NowPlayingMaxItems]
	}
	return all
}

// Titles finds a stored title; catalog.Store is one.
type Titles interface {
	Title(ctx context.Context, id uuid.UUID) (*core.Title, error)
}

// LoadLiveSet reads and computes the set for user.
func LoadLiveSet(ctx context.Context, store *Store, titles Titles, user uuid.UUID, now time.Time) ([]Entry, error) {
	open, err := store.OpenSessions(ctx, user, nil, 10)
	if err != nil {
		return nil, err
	}
	var sessions []SessionTitle
	for _, s := range open {
		if s.LibraryItemID == nil || !IsLive(s, now) {
			continue
		}
		t, err := titles.Title(ctx, s.TitleID)
		if err != nil {
			return nil, err
		}
		if t != nil {
			sessions = append(sessions, SessionTitle{Session: s, Title: *t})
		}
	}
	plays, err := store.LivePlays(ctx, user, now)
	if err != nil {
		return nil, err
	}
	return ComputeLiveSet(sessions, plays, now), nil
}
