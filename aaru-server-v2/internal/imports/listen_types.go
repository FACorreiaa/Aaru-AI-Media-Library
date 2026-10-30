package imports

// MUS-004 · the pieces of the listening log (Music/ListenTypes.swift, Music/ListenSubmission.swift)
// that listening-history imports need. The listening log itself (scrobble ingest, /v1/me/listens,
// MusicBrainz resolution) is ported in its own area; these are the minimal pure helpers an import
// stages plays with. When the log's package lands, the two copies of NewListen, TrackKey and the
// ListenBrainz page reader should become one.

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"golang.org/x/text/unicode/norm"
)

// NewListen is one play of a track as a file or a provider reported it, before it is stored.
type NewListen struct {
	ListenedAt       time.Time
	Artist           string
	Track            string
	Album            *string
	DurationMs       *int
	ISRC             *string
	RecordingMBID    *string
	ReleaseMBID      *string
	ReleaseGroupMBID *string
	ArtistMBID       *string
	SpotifyID        *string
	OriginURL        *string
	// Client is the scrobbler ("Web Scrobbler"); MusicService the service it heard ("YouTube Music").
	Client       *string
	MusicService *string
}

// TrackKey is the listen's artist and track, folded: what makes two spellings of one play the same.
func (l NewListen) TrackKey() string { return TrackKey(l.Artist, l.Track) }

// ListenHistoryPage is plays read from a file or one page of a provider: the listens, and how many
// plays were left out.
type ListenHistoryPage struct {
	Listens []NewListen
	Ignored int
}

// The limits a live listen is held to (ListenSubmission).
var (
	// listenEarliest is when Audioscrobbler began (2002-10-01): ListenBrainz refuses older listens.
	listenEarliest = time.Unix(1_033_430_400, 0).UTC()
	// listenFutureSlack forgives a clock slightly ahead; a listen from tomorrow is not.
	listenFutureSlack = time.Hour
)

const listenMaxText = 500

// TrackKey is the artist and track, case-, width- and space-folded, joined by a unit separator
// (Listen.trackKey). It must match the listening log's own key.
func TrackKey(artist, track string) string {
	return foldListenText(artist) + "\u001F" + foldListenText(track)
}

// foldListenText is Listen.fold: NFKC, lowercased, whitespace runs joined by one space. Swift's
// lowercased() maps each scalar fully and without context: per rune here, with U+0130's two-scalar
// mapping, so Greek final sigma is not special-cased (as in Swift).
func foldListenText(text string) string {
	composed := norm.NFKC.String(text)
	var b strings.Builder
	b.Grow(len(composed))
	for _, r := range composed {
		if r == '\u0130' {
			b.WriteString("i\u0307")
			continue
		}
		b.WriteRune(unicode.ToLower(r))
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// listenText is ListenSubmission.text: trimmed, at most 500 characters, nil when empty. Counted in
// runes, which is what the columns' char_length check counts.
func listenText(value *string) *string {
	if value == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*value)
	if trimmed == "" {
		return nil
	}
	if r := []rune(trimmed); len(r) > listenMaxText {
		trimmed = string(r[:listenMaxText])
	}
	return &trimmed
}

// listenTextOf is listenText of a plain string.
func listenTextOf(value string) *string { return listenText(&value) }

// listenMBID is ListenSubmission.mbid: a MusicBrainz id is a UUID in its 36-character form; anything
// else is dropped rather than stored. Lowercased.
func listenMBID(value *string) *string {
	if value == nil || len(*value) != 36 {
		return nil
	}
	id, err := uuid.Parse(*value)
	if err != nil {
		return nil
	}
	s := id.String()
	return &s
}

// plausibleListenTime is a play time a live listen would accept: after Audioscrobbler began, not in
// the future (ListenFileDetector.plausible).
func plausibleListenTime(date, now time.Time) bool {
	return !date.Before(listenEarliest) && !date.After(now.Add(listenFutureSlack))
}

// MARK: ListenBrainz history pages (ListenSubmission.historyPage)

var errNotListenBrainzPage = errors.New("the body is not a page of ListenBrainz listens")

type lbHistoryBody struct {
	Payload *struct {
		Listens []lbPayload `json:"listens"`
	} `json:"payload"`
}

type lbPayload struct {
	ListenedAt    *int64      `json:"listened_at"`
	TrackMetadata *lbMetadata `json:"track_metadata"`
}

type lbMetadata struct {
	ArtistName     *string         `json:"artist_name"`
	TrackName      *string         `json:"track_name"`
	ReleaseName    *string         `json:"release_name"`
	AdditionalInfo json.RawMessage `json:"additional_info"`
	MBIDMapping    json.RawMessage `json:"mbid_mapping"`
}

// listenBrainzHistoryPage is one page of a user's ListenBrainz history, read as a submission's
// listens are: a listen that would be refused live is left out and counted. oldest is the page's
// earliest time, which asks for the next page; nil when the page has none.
func listenBrainzHistoryPage(data []byte, now time.Time) (ListenHistoryPage, *int64, error) {
	var body lbHistoryBody
	if err := json.Unmarshal(data, &body); err != nil || body.Payload == nil || body.Payload.Listens == nil {
		return ListenHistoryPage{}, nil, errNotListenBrainzPage
	}
	var page ListenHistoryPage
	var oldest *int64
	for _, p := range body.Payload.Listens {
		if p.TrackMetadata == nil {
			return ListenHistoryPage{}, nil, errNotListenBrainzPage
		}
		info, ok := lbAdditionalInfo(p.TrackMetadata.AdditionalInfo)
		if !ok {
			return ListenHistoryPage{}, nil, errNotListenBrainzPage
		}
		if p.ListenedAt != nil && (oldest == nil || *p.ListenedAt < *oldest) {
			at := *p.ListenedAt
			oldest = &at
		}
		listen, ok := lbListen(p, info, now)
		if !ok {
			page.Ignored++
			continue
		}
		if listen.Client == nil {
			client := "ListenBrainz"
			listen.Client = &client
		}
		page.Listens = append(page.Listens, listen)
	}
	return page, oldest, nil
}

// lbListen is one history listen, or false when a live submission would refuse it.
func lbListen(p lbPayload, info lbInfo, now time.Time) (NewListen, bool) {
	meta := p.TrackMetadata
	artist, track := listenText(meta.ArtistName), listenText(meta.TrackName)
	if artist == nil || track == nil || p.ListenedAt == nil {
		return NewListen{}, false
	}
	at := time.Unix(*p.ListenedAt, 0).UTC()
	if !plausibleListenTime(at, now) {
		return NewListen{}, false
	}
	mapping := lbMapping(meta.MBIDMapping)
	origin := listenText(info.originURL)
	if origin != nil && !strings.HasPrefix(*origin, "https://") && !strings.HasPrefix(*origin, "http://") {
		origin = nil
	}
	client := info.submissionClient
	if client == nil {
		client = info.mediaPlayer
	}
	service := info.musicServiceName
	if service == nil {
		service = info.musicService
	}
	return NewListen{
		ListenedAt: at, Artist: *artist, Track: *track, Album: listenText(meta.ReleaseName),
		DurationMs: info.durationMs, ISRC: listenText(info.isrc),
		RecordingMBID:    firstMBID(info.recordingMBID, mapping.recordingMBID),
		ReleaseMBID:      firstMBID(info.releaseMBID, mapping.releaseMBID),
		ReleaseGroupMBID: listenMBID(info.releaseGroupMBID),
		ArtistMBID:       firstMBID(first(info.artistMBIDs), first(mapping.artistMBIDs)),
		SpotifyID:        listenText(info.spotifyID),
		OriginURL:        origin,
		Client:           listenText(client),
		MusicService:     listenText(service),
	}, true
}

func firstMBID(sent, matched *string) *string {
	if id := listenMBID(sent); id != nil {
		return id
	}
	return listenMBID(matched)
}

func first(values []string) *string {
	if len(values) == 0 {
		return nil
	}
	return &values[0]
}

// lbInfo is `additional_info`'s fields Aaru keeps, each read leniently: a field of an unexpected
// type is ignored, never a reason to refuse the listen.
type lbInfo struct {
	durationMs                                                    *int
	isrc, recordingMBID, releaseMBID, releaseGroupMBID, spotifyID *string
	originURL, musicService, musicServiceName                     *string
	submissionClient, mediaPlayer                                 *string
	artistMBIDs                                                   []string
}

// lbAdditionalInfo reads `additional_info`; false when it is there but not an object.
func lbAdditionalInfo(raw json.RawMessage) (lbInfo, bool) {
	var info lbInfo
	if len(raw) == 0 || string(raw) == "null" {
		return info, true
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return info, false
	}
	str := func(key string) *string {
		var s string
		if v, ok := fields[key]; ok && json.Unmarshal(v, &s) == nil {
			return &s
		}
		return nil
	}
	num := func(key string) *float64 {
		v, ok := fields[key]
		if !ok {
			return nil
		}
		var f float64
		if json.Unmarshal(v, &f) == nil {
			return &f
		}
		if s := str(key); s != nil {
			if f, err := strconv.ParseFloat(*s, 64); err == nil {
				return &f
			}
		}
		return nil
	}
	// `duration_ms`, or `duration` in seconds.
	ms := num("duration_ms")
	if ms == nil {
		if seconds := num("duration"); seconds != nil {
			v := *seconds * 1000
			ms = &v
		}
	}
	if ms != nil && *ms >= 1 && *ms < 86_400_000 {
		v := int(*ms)
		info.durationMs = &v
	}
	info.isrc = str("isrc")
	info.recordingMBID = str("recording_mbid")
	info.releaseMBID = str("release_mbid")
	info.releaseGroupMBID = str("release_group_mbid")
	if v, ok := fields["artist_mbids"]; ok {
		var ids []string
		if json.Unmarshal(v, &ids) == nil {
			info.artistMBIDs = ids
		}
	}
	info.spotifyID = str("spotify_id")
	info.originURL = str("origin_url")
	info.musicService = str("music_service")
	info.musicServiceName = str("music_service_name")
	info.submissionClient = str("submission_client")
	info.mediaPlayer = str("media_player")
	return info, true
}

type lbMatch struct {
	recordingMBID, releaseMBID *string
	artistMBIDs                []string
}

// lbMapping is what ListenBrainz matched a listen to: read leniently, an odd value is ignored.
func lbMapping(raw json.RawMessage) lbMatch {
	var m lbMatch
	var fields map[string]json.RawMessage
	if len(raw) == 0 || json.Unmarshal(raw, &fields) != nil {
		return m
	}
	str := func(key string) *string {
		var s string
		if v, ok := fields[key]; ok && json.Unmarshal(v, &s) == nil {
			return &s
		}
		return nil
	}
	m.recordingMBID = str("recording_mbid")
	m.releaseMBID = str("release_mbid")
	if v, ok := fields["artist_mbids"]; ok {
		var ids []string
		if json.Unmarshal(v, &ids) == nil {
			m.artistMBIDs = ids
		}
	}
	return m
}
