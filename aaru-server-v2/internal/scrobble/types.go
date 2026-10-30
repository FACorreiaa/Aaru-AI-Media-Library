// Package scrobble is SCR-001…011: players' playback reports become watch events and, at 80% or
// more, a library write through the same library path a tap uses; tracks and YouTube videos are
// plays; and the "Now playing" Live Activity follows everything that plays. It is the port of
// Sources/App/Scrobble, Push/LiveActivitySweepService.swift and PostgresWatchEventStore.swift.
//
// Other areas call: Service.Report and Service.MarkWatched/Resolve (the Stremio addon),
// Service.Play (ListenBrainz `playing_now`), Service.NowPlaying/PlayingNow (`/v1/me/now-playing`),
// Store.RegisterLiveActivity and Notifier.CaughtUp (`PUT /v1/devices/live-activity`).
package scrobble

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"time"

	"github.com/google/uuid"
)

// WatchSource is where a watch event came from: Stremio's addon, or a streaming site through the
// browser extension (SCR-007).
type WatchSource string

// The sources.
const (
	SourceStremio    WatchSource = "stremio"
	SourceNetflix    WatchSource = "netflix"
	SourceDisneyPlus WatchSource = "disney_plus"
	SourcePrimeVideo WatchSource = "prime_video"
)

// ParseWatchSource is a known source.
func ParseWatchSource(s string) (WatchSource, bool) {
	switch WatchSource(s) {
	case SourceStremio, SourceNetflix, SourceDisneyPlus, SourcePrimeVideo:
		return WatchSource(s), true
	}
	return "", false
}

// Label is how a person names the player.
func (s WatchSource) Label() string {
	switch s {
	case SourceStremio:
		return "Stremio"
	case SourceNetflix:
		return "Netflix"
	case SourceDisneyPlus:
		return "Disney+"
	case SourcePrimeVideo:
		return "Prime Video"
	}
	return string(s)
}

// Action is what a player reports.
type Action string

// The actions.
const (
	ActionStart Action = "start"
	ActionPause Action = "pause"
	ActionStop  Action = "stop"
)

// ParseAction is a known action.
func ParseAction(s string) (Action, bool) {
	switch Action(s) {
	case ActionStart, ActionPause, ActionStop:
		return Action(s), true
	}
	return "", false
}

// State is the stored state an action leaves: playing, paused or stopped.
func (a Action) State() string {
	switch a {
	case ActionPause:
		return "paused"
	case ActionStop:
		return "stopped"
	case ActionStart:
	}
	return "playing"
}

// State is an open session's or a play's state.
type State string

// The states.
const (
	Playing State = "playing"
	Paused  State = "paused"
)

// Report is one playback report from a player, already mapped to ids Aaru understands.
type Report struct {
	Source WatchSource
	// ExternalRef is the player's own id for what is playing, kept verbatim (e.g. `tt0903747:1:2`).
	ExternalRef string
	Type        core.MediaType
	IDs         core.ExternalIDs
	// TitleID is set when the player already names an Aaru title (Stremio's `aaru:` ids).
	TitleID *uuid.UUID
	// Episode is set for an episode; nil for a movie.
	Episode *core.EpisodeKey
	// Title: a player with no ids names what plays instead (SCR-007): matched by name, never guessed.
	Title *string
	// Year: with Title, matched by title + year when the player knows the year.
	Year *int
	// EpisodeName is the episode's own name, when the player gives no number Aaru can trust.
	EpisodeName *catalog.NamedEpisode
	Action      Action
	PositionMs  int64
	// DurationMs is 0 when the player does not know it yet (Stremio's first `start`).
	DurationMs int64
}

// Session is the open (or just closed) session a report landed in.
type Session struct {
	ID         uuid.UUID
	TitleID    *uuid.UUID
	PositionMs int64
	// DurationMs is the longest non-zero duration any report in this session gave.
	DurationMs int64
}

// Progress is percent watched; false while the duration is unknown.
func (s Session) Progress() (float64, bool) {
	if s.DurationMs <= 0 {
		return 0, false
	}
	return min(100, float64(s.PositionMs)/float64(s.DurationMs)*100), true
}

// OpenSession is a matched session no `stop` has closed yet, with what Home and the Live Activity
// show (SCR-008).
type OpenSession struct {
	ID          uuid.UUID
	Source      WatchSource
	ExternalRef string
	TitleID     uuid.UUID
	// LibraryItemID is nil when the title is not in the user's library yet.
	LibraryItemID *uuid.UUID
	Episode       *core.EpisodeKey
	EpisodeName   *string
	// RuntimeMinutes is the episode's runtime, else the title's.
	RuntimeMinutes *int
	State          State
	PositionMs     int64
	DurationMs     int64
	// UpdatedAt is when the player last reported. Stremio reports only on start, pause and stop.
	UpdatedAt time.Time
}

// KnownDurationMs is the player's duration, else the catalog runtime; 0 when neither is known.
func (s OpenSession) KnownDurationMs() int64 {
	if s.DurationMs > 0 {
		return s.DurationMs
	}
	if s.RuntimeMinutes == nil {
		return 0
	}
	return int64(*s.RuntimeMinutes) * 60000
}

// ReportedProgress is the reported progress in percent; false while no duration is known. Never
// extrapolated: a player closed mid-episode must not count as watched.
func (s OpenSession) ReportedProgress() (float64, bool) {
	if s.DurationMs <= 0 {
		return 0, false
	}
	return min(100, float64(s.PositionMs)/float64(s.DurationMs)*100), true
}

// PlayKind is what a play is.
type PlayKind string

// The kinds of play.
const (
	PlayTrack PlayKind = "track"
	PlayVideo PlayKind = "video"
)

// PlaySource is who reported a play.
type PlaySource string

// The play sources.
const (
	PlayListenBrainz PlaySource = "listenbrainz"
	PlayYouTube      PlaySource = "youtube"
)

// LivePlay is something a player reports that is not a Title (SCR-009): a scrobbler's
// `playing_now` track, or a YouTube video the browser extension reads. It lives only while it plays:
// never a listen or a watch event, and it never ticks anything.
type LivePlay struct {
	// ID is new for each thing played; kept while the same Ref plays on.
	ID     uuid.UUID
	Kind   PlayKind
	Source PlaySource
	// Ref is the recording's MBID or artist + track key; the video id.
	Ref   string
	Title string
	// Subtitle is the artist, or the channel.
	Subtitle *string
	// Service is "YouTube Music", "Web Scrobbler", "YouTube".
	Service    *string
	ArtworkURL *string
	OriginURL  *string
	State      State
	// PositionMs is where the player was at UpdatedAt. A track's `playing_now` says only that it began.
	PositionMs int64
	// DurationMs is 0 when unknown.
	DurationMs int64
	StartedAt  time.Time
	UpdatedAt  time.Time
	ExpiresAt  time.Time
}

// LiveActivityState is what the user's "Now playing" activity last showed (SCR-009), so a report
// pushes only when that changes. Version guards against two reports saving at once.
type LiveActivityState struct {
	// Pushed is nil while no activity runs.
	Pushed      *core.NowPlayingActivityState
	Lingering   []Lingering
	Version     int
	NextCheckAt *time.Time
}

// Lingering is a row that just ticked, kept on the activity a moment to read "Watched". Stored as
// Swift's Codable wrote it: dates as seconds since 2001.
type Lingering struct {
	Item  core.NowPlayingActivityItem `json:"item"`
	Until core.ReferenceTime          `json:"until"`
}
