package music

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// SubmissionKind is a ListenBrainz `listen_type`.
type SubmissionKind string

// The kinds.
const (
	KindSingle     SubmissionKind = "single"
	KindPlayingNow SubmissionKind = "playing_now"
	KindImport     SubmissionKind = "import"
)

// MaxListens is ListenBrainz's own limit on an import.
const MaxListens = 1000

// Earliest is the oldest listen ListenBrainz accepts: before Audioscrobbler existed (2002-10-01).
var Earliest = time.Unix(1_033_430_400, 0)

// FutureSlack forgives a clock slightly ahead; a listen from tomorrow is not.
const FutureSlack = time.Hour

// InvalidError is a submission refused with ListenBrainz's message.
type InvalidError struct{ Message string }

func (e *InvalidError) Error() string { return e.Message }

func invalid(message string) error { return &InvalidError{Message: message} }

// Submission is a ListenBrainz `submit-listens` body, checked: `single` and `import` carry listens
// with the time they started; `playing_now` carries one track and no time, and is no listen: it says
// what plays now (SCR-009).
type Submission struct {
	Kind    SubmissionKind
	Listens []NewListen
	// PlayingNow is the track a `playing_now` names; nil for any other kind.
	PlayingNow *NewListen
}

// ParseSubmission reads and checks a body, as ListenSubmission(json:now:) does.
func ParseSubmission(data []byte, now time.Time) (Submission, error) {
	var body submissionBody
	if err := json.Unmarshal(data, &body); err != nil || body.ListenType == nil || body.Payload == nil ||
		!allHaveMetadata(*body.Payload) {
		return Submission{}, invalid("The body is not a ListenBrainz submission.")
	}
	kind := SubmissionKind(*body.ListenType)
	switch kind {
	case KindSingle, KindPlayingNow:
		if len(*body.Payload) != 1 {
			return Submission{}, invalid(fmt.Sprintf("%s carries exactly one listen.", kind))
		}
	case KindImport:
		if n := len(*body.Payload); n < 1 || n > MaxListens {
			return Submission{}, invalid(fmt.Sprintf("An import carries 1 to %d listens.", MaxListens))
		}
	default:
		return Submission{}, invalid("listen_type must be single, playing_now or import.")
	}
	parsed := make([]NewListen, 0, len(*body.Payload))
	for _, p := range *body.Payload {
		l, err := parseListen(p, kind, now)
		if err != nil {
			return Submission{}, err
		}
		parsed = append(parsed, l)
	}
	if kind == KindPlayingNow {
		return Submission{Kind: kind, Listens: []NewListen{}, PlayingNow: &parsed[0]}, nil
	}
	return Submission{Kind: kind, Listens: parsed}, nil
}

func parseListen(p payload, kind SubmissionKind, now time.Time) (NewListen, error) {
	m := p.TrackMetadata
	artist, track := Text(m.ArtistName), Text(m.TrackName)
	if artist == nil || track == nil {
		return NewListen{}, invalid("Every listen needs artist_name and track_name.")
	}
	listenedAt := now
	if kind != KindPlayingNow {
		if p.ListenedAt == nil {
			return NewListen{}, invalid("Every listen needs listened_at.")
		}
		listenedAt = time.Unix(*p.ListenedAt, 0)
		if listenedAt.Before(Earliest) || listenedAt.After(now.Add(FutureSlack)) {
			return NewListen{}, invalid("listened_at is not a plausible time.")
		}
	}
	info := m.AdditionalInfo
	mapping := m.MBIDMapping
	if info == nil {
		info = &additionalInfo{}
	}
	if mapping == nil {
		mapping = &mbidMapping{}
	}
	var origin *string
	if o := Text(info.OriginURL); o != nil && (strings.HasPrefix(*o, "https://") || strings.HasPrefix(*o, "http://")) {
		origin = o
	}
	return NewListen{
		ListenedAt: listenedAt, Artist: *artist, Track: *track, Album: Text(m.ReleaseName),
		DurationMs: info.DurationMs, ISRC: Text(info.ISRC),
		// ListenBrainz's own match (history pages only) fills what the scrobbler did not send.
		RecordingMBID:    firstMBID(info.RecordingMBID, mapping.RecordingMBID),
		ReleaseMBID:      firstMBID(info.ReleaseMBID, mapping.ReleaseMBID),
		ReleaseGroupMBID: MBID(info.ReleaseGroupMBID),
		ArtistMBID:       firstMBID(first(info.ArtistMBIDs), first(mapping.ArtistMBIDs)),
		SpotifyID:        Text(info.SpotifyID),
		OriginURL:        origin,
		Client:           Text(coalesce(info.SubmissionClient, info.MediaPlayer)),
		MusicService:     Text(coalesce(info.MusicServiceName, info.MusicService)),
	}, nil
}

// allHaveMetadata: `track_metadata` is required; without it the body does not decode.
func allHaveMetadata(payloads []payload) bool {
	for _, p := range payloads {
		if p.TrackMetadata == nil {
			return false
		}
	}
	return true
}

func firstMBID(a, b *string) *string {
	if id := MBID(a); id != nil {
		return id
	}
	return MBID(b)
}

func first(values []string) *string {
	if len(values) == 0 {
		return nil
	}
	return &values[0]
}

func coalesce(a, b *string) *string {
	if a != nil {
		return a
	}
	return b
}

// HistoryPage is one page of a user's ListenBrainz history (MUS-004).
type HistoryPage struct {
	Listens []NewListen
	// Ignored counts listens that would be refused live.
	Ignored int
}

// ParseHistoryPage reads a page of `GET /1/user/{name}/listens` as a submission's listens are read: a
// listen that would be refused live is left out and counted. oldest is the page's earliest time, which
// asks for the next page; nil when the page is empty.
func ParseHistoryPage(data []byte, now time.Time) (HistoryPage, *int64, error) {
	var body struct {
		Payload *struct {
			Listens *[]payload `json:"listens"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(data, &body); err != nil || body.Payload == nil || body.Payload.Listens == nil ||
		!allHaveMetadata(*body.Payload.Listens) {
		return HistoryPage{}, nil, invalid("The body is not a page of ListenBrainz listens.")
	}
	page := HistoryPage{Listens: []NewListen{}}
	var oldest *int64
	for _, p := range *body.Payload.Listens {
		if p.ListenedAt != nil && (oldest == nil || *p.ListenedAt < *oldest) {
			v := *p.ListenedAt
			oldest = &v
		}
		l, err := parseListen(p, KindImport, now)
		if err != nil {
			page.Ignored++
			continue
		}
		if l.Client == nil {
			c := "ListenBrainz"
			l.Client = &c
		}
		page.Listens = append(page.Listens, l)
	}
	return page, oldest, nil
}

// MARK: ListenBrainz's JSON

type submissionBody struct {
	ListenType *string    `json:"listen_type"`
	Payload    *[]payload `json:"payload"`
}

type payload struct {
	ListenedAt    *int64         `json:"listened_at"`
	TrackMetadata *trackMetadata `json:"track_metadata"`
}

type trackMetadata struct {
	ArtistName     *string         `json:"artist_name"`
	TrackName      *string         `json:"track_name"`
	ReleaseName    *string         `json:"release_name"`
	AdditionalInfo *additionalInfo `json:"additional_info"`
	MBIDMapping    *mbidMapping    `json:"mbid_mapping"`
}

// mbidMapping is what ListenBrainz matched a listen to, on history pages only. Read leniently: an
// odd value is ignored, never a reason to refuse the listen.
type mbidMapping struct {
	RecordingMBID *string
	ReleaseMBID   *string
	ArtistMBIDs   []string
}

func (m *mbidMapping) UnmarshalJSON(data []byte) error {
	var fields map[string]json.RawMessage
	if json.Unmarshal(data, &fields) != nil {
		*m = mbidMapping{}
		return nil
	}
	m.RecordingMBID = lenientString(fields["recording_mbid"])
	m.ReleaseMBID = lenientString(fields["release_mbid"])
	m.ArtistMBIDs = lenientStrings(fields["artist_mbids"])
	return nil
}

// additionalInfo is free-form; the fields Aaru keeps are read leniently and a field of an unexpected
// type is ignored, never a reason to refuse the listen. It must still be an object.
type additionalInfo struct {
	DurationMs       *int
	ISRC             *string
	RecordingMBID    *string
	ReleaseMBID      *string
	ReleaseGroupMBID *string
	ArtistMBIDs      []string
	SpotifyID        *string
	OriginURL        *string
	MusicService     *string
	MusicServiceName *string
	SubmissionClient *string
	MediaPlayer      *string
}

func (a *additionalInfo) UnmarshalJSON(data []byte) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	// `duration_ms`, or `duration` in seconds.
	ms := lenientNumber(fields["duration_ms"])
	if ms == nil {
		if s := lenientNumber(fields["duration"]); s != nil {
			v := *s * 1000
			ms = &v
		}
	}
	if ms != nil && *ms >= 1 && *ms < 86_400_000 {
		v := int(*ms)
		a.DurationMs = &v
	}
	a.ISRC = lenientString(fields["isrc"])
	a.RecordingMBID = lenientString(fields["recording_mbid"])
	a.ReleaseMBID = lenientString(fields["release_mbid"])
	a.ReleaseGroupMBID = lenientString(fields["release_group_mbid"])
	a.ArtistMBIDs = lenientStrings(fields["artist_mbids"])
	a.SpotifyID = lenientString(fields["spotify_id"])
	a.OriginURL = lenientString(fields["origin_url"])
	a.MusicService = lenientString(fields["music_service"])
	a.MusicServiceName = lenientString(fields["music_service_name"])
	a.SubmissionClient = lenientString(fields["submission_client"])
	a.MediaPlayer = lenientString(fields["media_player"])
	return nil
}

func lenientString(raw json.RawMessage) *string {
	var s string
	if len(raw) == 0 || json.Unmarshal(raw, &s) != nil {
		return nil
	}
	return &s
}

func lenientStrings(raw json.RawMessage) []string {
	var s []string
	if len(raw) == 0 || json.Unmarshal(raw, &s) != nil {
		return nil
	}
	return s
}

// lenientNumber is a number, or a string holding one.
func lenientNumber(raw json.RawMessage) *float64 {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || bytes.Equal(raw, []byte("null")) {
		return nil
	}
	var f float64
	if json.Unmarshal(raw, &f) == nil {
		return &f
	}
	if s := lenientString(raw); s != nil {
		if v, err := strconv.ParseFloat(*s, 64); err == nil {
			return &v
		}
	}
	return nil
}
