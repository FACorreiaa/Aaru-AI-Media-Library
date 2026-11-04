package imports

// MUS-004 · listening history files (Imports/Listens/ListenFileParsers.swift). Each parser keeps
// only what a listen stores and counts what it leaves out by rule; nothing else in the file is read
// into a row.

import (
	"aaru-go-api/internal/core"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"time"
)

// DetectListenFile picks the parser for a JSON upload when the person did not say which service
// it came from (ListenFileDetector.detect).
func DetectListenFile(data []byte) (core.ImportSource, error) {
	// Only ASCII keys are looked for, so the bytes are searched as they are.
	head := data[:min(len(data), 64*1024)]
	start := bytes.TrimLeft(head, " \t\n\r\v\f\u0085\u00a0\ufeff")
	if bytes.HasPrefix(start, []byte("PK\x03\x04")) {
		return "", formatError("This is a .zip file. Unzip it and add each Streaming_History_Audio file, one at a time.")
	}
	has := func(key string) bool { return bytes.Contains(head, []byte(key)) }
	if has(`"ms_played"`) && has(`"ts"`) {
		return core.SourceSpotifyJSON, nil
	}
	if has(`"msPlayed"`) && has(`"endTime"`) {
		return "", formatError("This is Spotify's account data, which has only the last year without track ids. " +
			"Ask Spotify for your Extended streaming history instead, then add its " +
			"Streaming_History_Audio files.")
	}
	if has(`"header"`) && has(`"time"`) && has(`"titleUrl"`) {
		return core.SourceYouTubeTakeout, nil
	}
	return "", formatError("Aaru reads Spotify's Extended streaming history and Google Takeout's YouTube " +
		"watch-history.json. For other sites, export a CSV.")
}

// ParseListenFile is the JSON file's plays, read by the source's parser.
func ParseListenFile(data []byte, source core.ImportSource, now time.Time) (ListenHistoryPage, error) {
	switch source {
	case core.SourceSpotifyJSON:
		return ParseSpotifyHistory(data, now)
	case core.SourceYouTubeTakeout:
		return ParseYouTubeTakeout(data, now)
	}
	return ListenHistoryPage{}, formatError("That is not a listening history file.")
}

// listenFileDate is an ISO 8601 time, with or without fractional seconds.
func listenFileDate(text *string) *time.Time {
	if text == nil {
		return nil
	}
	t, err := time.Parse(time.RFC3339Nano, *text)
	if err != nil {
		return nil
	}
	return &t
}

// eachJSONObject streams a JSON array of objects into T, one element at a time, so a large file is
// never held twice (PERF-001). False when the file is not such an array: anything else at the top,
// a null or non-object element, or anything after the closing bracket. Keys match as encoding/json
// matches struct fields, which also accepts another case; the files read here never use one.
func eachJSONObject[T any](data []byte, each func(*T)) bool {
	dec := json.NewDecoder(bytes.NewReader(data))
	open, err := dec.Token()
	if err != nil || open != json.Delim('[') {
		return false
	}
	for dec.More() {
		var item *T
		if err := dec.Decode(&item); err != nil || item == nil {
			return false
		}
		each(item)
	}
	if _, err := dec.Token(); err != nil {
		return false
	}
	_, err = dec.Token()
	return errors.Is(err, io.EOF)
}

// lenient is a field's value, nil when it is missing, null or of another type.
type lenient[T any] struct {
	v *T
}

// UnmarshalJSON never fails: a value of another type is the same as none.
func (l *lenient[T]) UnmarshalJSON(raw []byte) error {
	var v *T
	if json.Unmarshal(raw, &v) != nil {
		v = nil
	}
	l.v = v
	return nil
}

// MARK: Spotify

// spotifyShortestPlayMs is the shortest Spotify play that is a listen.
const spotifyShortestPlayMs = 30000

// ParseSpotifyHistory reads one `Streaming_History_Audio_*.json` from Spotify's extended streaming
// history. `ts` is when a play ended, so the listen starts `ms_played` before it: the moment a
// scrobbler would have sent. Podcast episodes, audiobooks and plays under 30 s are left out. The
// file's IP address, country and device are never read.
func ParseSpotifyHistory(data []byte, now time.Time) (ListenHistoryPage, error) {
	var page ListenHistoryPage
	ok := eachJSONObject(data, func(play *spotifyPlay) {
		if listen, ok := spotifyListen(play, now); ok {
			page.Listens = append(page.Listens, listen)
		} else {
			page.Ignored++
		}
	})
	if !ok {
		return ListenHistoryPage{}, formatError("That file is not a Spotify streaming history.")
	}
	return page, nil
}

// spotifyPlay is one entry of the file, the fields Aaru reads, each leniently.
type spotifyPlay struct {
	TS                    lenient[string] `json:"ts"`
	MsPlayed              lenient[int]    `json:"ms_played"`
	Artist                lenient[string] `json:"master_metadata_album_artist_name"`
	Track                 lenient[string] `json:"master_metadata_track_name"`
	Album                 lenient[string] `json:"master_metadata_album_album_name"`
	TrackURI              lenient[string] `json:"spotify_track_uri"`
	EpisodeName           lenient[string] `json:"episode_name"`
	AudiobookTitle        lenient[string] `json:"audiobook_title"`
	AudiobookChapterTitle lenient[string] `json:"audiobook_chapter_title"`
}

func spotifyListen(play *spotifyPlay, now time.Time) (NewListen, bool) {
	played := play.MsPlayed.v
	if play.EpisodeName.v != nil || play.AudiobookTitle.v != nil || play.AudiobookChapterTitle.v != nil ||
		played == nil || *played < spotifyShortestPlayMs {
		return NewListen{}, false
	}
	ended := listenFileDate(play.TS.v)
	artist := listenText(play.Artist.v)
	track := listenText(play.Track.v)
	if ended == nil || artist == nil || track == nil {
		return NewListen{}, false
	}
	started := ended.Add(-time.Duration(*played) * time.Millisecond).UTC()
	if !plausibleListenTime(started, now) {
		return NewListen{}, false
	}
	var trackID *string
	if uri := play.TrackURI.v; uri != nil && strings.HasPrefix(*uri, "spotify:track:") {
		trackID = listenTextOf(strings.TrimPrefix(*uri, "spotify:track:"))
	}
	service := "Spotify"
	duration := *played
	// Spotify gives the time heard, not the track's length: that is what Insights adds up.
	return NewListen{
		ListenedAt: started, Artist: *artist, Track: *track, Album: listenText(play.Album.v),
		DurationMs: &duration, SpotifyID: trackID, MusicService: &service,
	}, true
}

// MARK: Google Takeout

const (
	youTubeTopicSuffix = " - Topic"
	// youTubeTitlesForVerb is the distinct titles needed before the words they all start with count
	// as the verb.
	youTubeTitlesForVerb = 10
)

// youTubeKnownVerbs is the English verb in front of every title. Other languages' is found from the
// file itself.
var youTubeKnownVerbs = []string{"Watched "}

// takeoutEntry is one entry of Takeout's watch history, the fields Aaru reads, each leniently.
type takeoutEntry struct {
	header, title, titleURL, time *string
	subtitles, details            []*string
}

// takeoutJSON is the entry as the file has it.
type takeoutJSON struct {
	Header    lenient[string]      `json:"header"`
	Title     lenient[string]      `json:"title"`
	TitleURL  lenient[string]      `json:"titleUrl"`
	Time      lenient[string]      `json:"time"`
	Subtitles lenient[[]namedJSON] `json:"subtitles"`
	Details   lenient[[]namedJSON] `json:"details"`
}

type namedJSON struct {
	Name *string `json:"name"`
}

func names(list *[]namedJSON) []*string {
	if list == nil {
		return nil
	}
	out := make([]*string, len(*list))
	for i, n := range *list {
		out[i] = n.Name
	}
	return out
}

func takeoutEntries(data []byte) ([]takeoutEntry, bool) {
	var entries []takeoutEntry
	ok := eachJSONObject(data, func(o *takeoutJSON) {
		entries = append(entries, takeoutEntry{
			header: o.Header.v, title: o.Title.v, titleURL: o.TitleURL.v, time: o.Time.v,
			subtitles: names(o.Subtitles.v), details: names(o.Details.v),
		})
	})
	return entries, ok
}

// ParseYouTubeTakeout reads Google Takeout's `watch-history.json` (decisions 2026-10-27): music
// only, nothing guessed. A YouTube Music entry is music; a YouTube entry is music only from an
// auto-generated "… - Topic" channel, whose name is the artist's and whose videos are named for the
// track. Ads and every other video are left out. No length is known, so the 30 s window applies.
func ParseYouTubeTakeout(data []byte, now time.Time) (ListenHistoryPage, error) {
	entries, ok := takeoutEntries(data)
	if !ok {
		return ListenHistoryPage{}, formatError("That file is not a YouTube watch history.")
	}
	type candidate struct {
		entry    takeoutEntry
		artist   string
		playedAt time.Time
	}
	var page ListenHistoryPage
	var music []candidate
	var titles []string
	for _, entry := range entries {
		if entry.title != nil {
			titles = append(titles, *entry.title)
		}
		artist := takeoutArtist(entry)
		playedAt := listenFileDate(entry.time)
		if artist != nil && playedAt != nil && plausibleListenTime(*playedAt, now) &&
			entry.titleURL != nil && strings.HasPrefix(*entry.titleURL, "https://") {
			music = append(music, candidate{entry: entry, artist: *artist, playedAt: playedAt.UTC()})
		} else {
			page.Ignored++
		}
	}
	// Every title in the file shares the verb, music or not: the more kinds of title, the surer.
	verb := youTubeFileVerb(titles)
	for _, c := range music {
		track := youTubeTrack(c.entry.title, verb)
		if track == nil {
			page.Ignored++
			continue
		}
		page.Listens = append(page.Listens, NewListen{
			ListenedAt: c.playedAt, Artist: c.artist, Track: *track,
			OriginURL: c.entry.titleURL, MusicService: c.entry.header,
		})
	}
	return page, nil
}

// takeoutArtist is the artist when the entry is music, else nil.
func takeoutArtist(entry takeoutEntry) *string {
	for _, d := range entry.details {
		if d != nil && *d == "From Google Ads" {
			return nil
		}
	}
	if len(entry.subtitles) == 0 || entry.subtitles[0] == nil || entry.header == nil {
		return nil
	}
	channel := *entry.subtitles[0]
	switch *entry.header {
	case "YouTube Music":
		name := strings.TrimSuffix(channel, youTubeTopicSuffix)
		if strings.HasSuffix(name, "VEVO") && core.Length(name) > 4 {
			name = strings.TrimSuffix(name, "VEVO")
		}
		return listenTextOf(name)
	case "YouTube":
		if !strings.HasSuffix(channel, youTubeTopicSuffix) {
			return nil
		}
		return listenTextOf(strings.TrimSuffix(channel, youTubeTopicSuffix))
	}
	return nil
}

// youTubeFileVerb is the words every title starts with, when the file is in a language Aaru has no
// verb for: what enough distinct titles share, cut back to a whole word. Titles that all begin with
// the same word would lose it too; a whole watch history, videos included, practically never does.
func youTubeFileVerb(titles []string) *string {
	unknown := map[string]bool{}
	for _, title := range titles {
		known := false
		for _, v := range youTubeKnownVerbs {
			if strings.HasPrefix(title, v) {
				known = true
				break
			}
		}
		if !known {
			unknown[title] = true
		}
	}
	if len(unknown) < youTubeTitlesForVerb {
		return nil
	}
	var prefix []rune
	started := false
	for title := range unknown {
		r := []rune(title)
		if !started {
			prefix, started = r, true
			continue
		}
		n := 0
		for n < len(prefix) && n < len(r) && prefix[n] == r[n] {
			n++
		}
		prefix = prefix[:n]
	}
	text := string(prefix)
	space := strings.LastIndex(text, " ")
	if space < 0 {
		return nil
	}
	verb := text[:space+1]
	return &verb
}

// youTubeTrack is the track: the title without its verb. A removed video's title is only its link.
func youTubeTrack(title, verb *string) *string {
	if title == nil {
		return nil
	}
	verbs := youTubeKnownVerbs
	if verb != nil {
		verbs = append(append([]string{}, youTubeKnownVerbs...), *verb)
	}
	for _, v := range verbs {
		if strings.HasPrefix(*title, v) {
			name := strings.TrimPrefix(*title, v)
			if strings.HasPrefix(name, "https://") || strings.HasPrefix(name, "http://") {
				return nil
			}
			return listenTextOf(name)
		}
	}
	return nil
}
