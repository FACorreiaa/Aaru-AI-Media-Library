package core

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ReferenceTime encodes as Foundation's default date: seconds since 2001-01-01 UTC,
// which is what ActivityKit decodes from a push.
type ReferenceTime struct {
	time.Time
}

// referenceEpoch is Foundation's reference date.
var referenceEpoch = time.Date(2001, 1, 1, 0, 0, 0, 0, time.UTC)

// MarshalJSON writes seconds since 2001 as a number.
func (t ReferenceTime) MarshalJSON() ([]byte, error) {
	return json.Marshal(t.Sub(referenceEpoch).Seconds())
}

// UnmarshalJSON reads seconds since 2001.
func (t *ReferenceTime) UnmarshalJSON(data []byte) error {
	var seconds float64
	if err := json.Unmarshal(data, &seconds); err != nil {
		return err
	}
	t.Time = referenceEpoch.Add(time.Duration(seconds * float64(time.Second)))
	return nil
}

// AppleUUID encodes as Foundation does: upper case.
type AppleUUID uuid.UUID

// MarshalJSON writes the upper-case form.
func (u AppleUUID) MarshalJSON() ([]byte, error) {
	return json.Marshal(strings.ToUpper(uuid.UUID(u).String()))
}

// UnmarshalJSON reads any case.
func (u *AppleUUID) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return err
	}
	id, err := uuid.Parse(s)
	if err != nil {
		return err
	}
	*u = AppleUUID(id)
	return nil
}

// NowWatchingAttributes is the "Now watching" Live Activity's fixed part (WID-005,
// SCR-008). The app starts it by hand or when it sees a scrobble; the server starts
// it by push (`attributes-type: NowWatchingAttributes`). Both encode this one shape.
type NowWatchingAttributes struct {
	LibraryItemID  string  `json:"libraryItemId"`
	Title          string  `json:"title"`
	Season         int     `json:"season"`
	Episode        int     `json:"episode"`
	EpisodeName    *string `json:"episodeName,omitempty"`
	PosterURL      *string `json:"posterURL,omitempty"`
	RuntimeMinutes int     `json:"runtimeMinutes"`
	// WatchEventID is the scrobble session this activity follows; nil for one started by hand.
	WatchEventID *AppleUUID `json:"watchEventId,omitempty"`
}

// EpisodeLine is "S1 · E8 · Lanterns".
func (a NowWatchingAttributes) EpisodeLine() string {
	line := fmt.Sprintf("S%d · E%d", a.Season, a.Episode)
	if a.EpisodeName != nil {
		line += " · " + *a.EpisodeName
	}
	return line
}

// Matches is whether the activity is for this item's episode.
func (a NowWatchingAttributes) Matches(libraryItemID string, season, episode int) bool {
	return a.LibraryItemID == libraryItemID && a.Season == season && a.Episode == episode
}

// NowWatchingContent is the Live Activity's changing part.
type NowWatchingContent struct {
	StartedAt ReferenceTime `json:"startedAt"`
	EndsAt    ReferenceTime `json:"endsAt"`
	// ShowsEndTime reads "Ends at 1:20 PM" instead of "41m left".
	ShowsEndTime bool `json:"showsEndTime"`
	// Watched is set just before the activity ends, so its last frame says so.
	Watched bool `json:"watched"`
	// PausedAt is set while the player is paused: progress stands still at this moment.
	PausedAt *ReferenceTime `json:"pausedAt,omitempty"`
}

// NowPlayingActivityAttributes is the "Now playing" Live Activity's fixed part
// (SCR-009): one activity per device shows everything that plays at once, so it is empty.
type NowPlayingActivityAttributes struct{}

// NowPlayingMaxItems is the most rows the activity shows.
const NowPlayingMaxItems = 3

// NowPlayingActivityState is the activity's changing part: what plays now, primary first.
type NowPlayingActivityState struct {
	// Items are at most NowPlayingMaxItems: catalog episodes, movies and videos first,
	// newest first, then tracks.
	Items        []NowPlayingActivityItem `json:"items"`
	ShowsEndTime bool                     `json:"showsEndTime"`
}

// NowPlayingKind is what one row of the activity plays.
type NowPlayingKind string

// The kinds of row.
const (
	NowPlayingEpisode NowPlayingKind = "episode"
	NowPlayingMovie   NowPlayingKind = "movie"
	NowPlayingTrack   NowPlayingKind = "track"
	NowPlayingVideo   NowPlayingKind = "video"
)

// NowPlayingActivityItem is one row of the activity: a library episode or movie, a track, or a video.
type NowPlayingActivityItem struct {
	// ID is the watch event or the play: stable while the same thing plays.
	ID   string         `json:"id"`
	Kind NowPlayingKind `json:"kind"`
	// Title is the show, film, track or video name.
	Title string `json:"title"`
	// Subtitle is "S1 · E8 · Lanterns", the artist, or the channel.
	Subtitle *string `json:"subtitle,omitempty"`
	// Service is where it plays: "Stremio", "Netflix", "YouTube Music".
	Service *string `json:"service,omitempty"`
	// StartedAt is when playback would have started had it run without a break.
	StartedAt ReferenceTime  `json:"startedAt"`
	EndsAt    *ReferenceTime `json:"endsAt,omitempty"`
	PausedAt  *ReferenceTime `json:"pausedAt,omitempty"`
	// Watched is set when the episode or movie just ticked.
	Watched bool `json:"watched"`
	// LibraryItemID, Season and Episode are for episodes and movies only.
	LibraryItemID *string `json:"libraryItemId,omitempty"`
	Season        *int    `json:"season,omitempty"`
	Episode       *int    `json:"episode,omitempty"`
	// ArtworkURL is the poster, cover or thumbnail.
	ArtworkURL *string `json:"artworkURL,omitempty"`
}
