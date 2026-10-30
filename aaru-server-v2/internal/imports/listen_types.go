package imports

// MUS-004 · the pieces of the listening log (Music/ListenTypes.swift, Music/ListenSubmission.swift)
// that listening-history imports stage plays with. They are the log's own (package music), so an
// imported play and a scrobbled one share one track key, one text limit and one page reader.

import (
	"aaru-go-api/internal/music"
	"time"
)

// NewListen is one play of a track as a file or a provider reported it, before it is stored.
type NewListen = music.NewListen

// ListenHistoryPage is plays read from a file or one page of a provider: the listens, and how many
// plays were left out.
type ListenHistoryPage = music.HistoryPage

// TrackKey is the listening log's key for an artist and track.
func TrackKey(artist, track string) string { return music.TrackKey(artist, track) }

// listenText is ListenSubmission.text: trimmed, at most 500 characters, nil when empty.
func listenText(value *string) *string { return music.Text(value) }

// listenTextOf is listenText of a plain string.
func listenTextOf(value string) *string { return music.Text(&value) }

// listenMBID is ListenSubmission.mbid: a MusicBrainz id in its 36-character form, lowercased.
func listenMBID(value *string) *string { return music.MBID(value) }

// plausibleListenTime is a play time a live listen would accept: after Audioscrobbler began, not in
// the future (ListenFileDetector.plausible).
func plausibleListenTime(date, now time.Time) bool {
	return !date.Before(music.Earliest) && !date.After(now.Add(music.FutureSlack))
}

// listenBrainzHistoryPage is one page of a user's ListenBrainz history, read as a submission's
// listens are. oldest is the page's earliest time; nil when the page has none.
func listenBrainzHistoryPage(data []byte, now time.Time) (ListenHistoryPage, *int64, error) {
	return music.ParseHistoryPage(data, now)
}
