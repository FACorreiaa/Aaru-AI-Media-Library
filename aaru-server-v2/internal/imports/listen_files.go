package imports

// MUS-004 · listening history files (Imports/Listens/ListenFileParsers.swift). Each parser keeps
// only what a listen stores and counts what it leaves out by rule; nothing else in the file is read
// into a row.

import (
	"aaru-go-api/internal/core"
	"bytes"
	"encoding/json"
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

// jsonObjects is a JSON array of objects, each as its raw fields; false when the file is not one.
func jsonObjects(data []byte) ([]map[string]json.RawMessage, bool) {
	var items []json.RawMessage
	if err := json.Unmarshal(data, &items); err != nil || items == nil {
		return nil, false
	}
	out := make([]map[string]json.RawMessage, 0, len(items))
	for _, raw := range items {
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(raw, &fields); err != nil || fields == nil {
			return nil, false
		}
		out = append(out, fields)
	}
	return out, true
}

// lenientString is a field's string, nil when it is missing, null or not a string.
func lenientString(fields map[string]json.RawMessage, key string) *string {
	raw, ok := fields[key]
	if !ok {
		return nil
	}
	var s *string
	if json.Unmarshal(raw, &s) != nil {
		return nil
	}
	return s
}

// MARK: Spotify

// spotifyShortestPlayMs is the shortest Spotify play that is a listen.
const spotifyShortestPlayMs = 30000

// ParseSpotifyHistory reads one `Streaming_History_Audio_*.json` from Spotify's extended streaming
// history. `ts` is when a play ended, so the listen starts `ms_played` before it: the moment a
// scrobbler would have sent. Podcast episodes, audiobooks and plays under 30 s are left out. The
// file's IP address, country and device are never read.
func ParseSpotifyHistory(data []byte, now time.Time) (ListenHistoryPage, error) {
	plays, ok := jsonObjects(data)
	if !ok {
		return ListenHistoryPage{}, formatError("That file is not a Spotify streaming history.")
	}
	var page ListenHistoryPage
	for _, play := range plays {
		if listen, ok := spotifyListen(play, now); ok {
			page.Listens = append(page.Listens, listen)
		} else {
			page.Ignored++
		}
	}
	return page, nil
}

func spotifyListen(play map[string]json.RawMessage, now time.Time) (NewListen, bool) {
	str := func(key string) *string { return lenientString(play, key) }
	var played *int
	if raw, ok := play["ms_played"]; ok {
		var v *int
		if json.Unmarshal(raw, &v) == nil {
			played = v
		}
	}
	if str("episode_name") != nil || str("audiobook_title") != nil || str("audiobook_chapter_title") != nil ||
		played == nil || *played < spotifyShortestPlayMs {
		return NewListen{}, false
	}
	ended := listenFileDate(str("ts"))
	artist := listenText(str("master_metadata_album_artist_name"))
	track := listenText(str("master_metadata_track_name"))
	if ended == nil || artist == nil || track == nil {
		return NewListen{}, false
	}
	started := ended.Add(-time.Duration(*played) * time.Millisecond).UTC()
	if !plausibleListenTime(started, now) {
		return NewListen{}, false
	}
	var trackID *string
	if uri := str("spotify_track_uri"); uri != nil && strings.HasPrefix(*uri, "spotify:track:") {
		trackID = listenTextOf(strings.TrimPrefix(*uri, "spotify:track:"))
	}
	service := "Spotify"
	duration := *played
	// Spotify gives the time heard, not the track's length: that is what Insights adds up.
	return NewListen{
		ListenedAt: started, Artist: *artist, Track: *track, Album: listenText(str("master_metadata_album_album_name")),
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

func takeoutEntries(data []byte) ([]takeoutEntry, bool) {
	objects, ok := jsonObjects(data)
	if !ok {
		return nil, false
	}
	named := func(fields map[string]json.RawMessage, key string) []*string {
		raw, ok := fields[key]
		if !ok {
			return nil
		}
		var list []struct {
			Name *string `json:"name"`
		}
		if json.Unmarshal(raw, &list) != nil {
			return nil
		}
		out := make([]*string, len(list))
		for i, n := range list {
			out[i] = n.Name
		}
		return out
	}
	entries := make([]takeoutEntry, 0, len(objects))
	for _, o := range objects {
		entries = append(entries, takeoutEntry{
			header: lenientString(o, "header"), title: lenientString(o, "title"),
			titleURL: lenientString(o, "titleUrl"), time: lenientString(o, "time"),
			subtitles: named(o, "subtitles"), details: named(o, "details"),
		})
	}
	return entries, true
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
		if strings.HasSuffix(name, "VEVO") && len([]rune(name)) > 4 {
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
