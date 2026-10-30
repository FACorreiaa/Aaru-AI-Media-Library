package scrobble

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/music"
	"encoding/json"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// InvalidError is a scrobble body refused with a reason.
type InvalidError struct{ Message string }

func (e *InvalidError) Error() string { return e.Message }

func invalid(message string) error { return &InvalidError{Message: message} }

// Body is Trakt's scrobble body: `movie`, or `show` + `episode`, and `progress` in percent. Aaru adds
// `source` (the streaming site) and `ref` (the player's own id for what plays: one film or one
// episode). `durationMs` is optional; without it progress is all Aaru keeps. A YouTube video (SCR-009)
// comes as `source: youtube` with `video` instead of `movie` or `show`.
type Body struct {
	Source     string       `json:"source"`
	Ref        string       `json:"ref"`
	Movie      *BodyItem    `json:"movie"`
	Show       *BodyItem    `json:"show"`
	Episode    *BodyEpisode `json:"episode"`
	Video      *BodyVideo   `json:"video"`
	Progress   float64      `json:"progress"`
	DurationMs *int64       `json:"durationMs"`
}

// BodyItem is a film or a show.
type BodyItem struct {
	Title *string  `json:"title"`
	Year  *int     `json:"year"`
	IDs   *BodyIDs `json:"ids"`
}

// BodyEpisode is the episode of a show.
type BodyEpisode struct {
	Season *int    `json:"season"`
	Number *int    `json:"number"`
	Title  *string `json:"title"`
}

// BodyVideo is a YouTube video (SCR-009).
type BodyVideo struct {
	ID      string  `json:"id"`
	Title   string  `json:"title"`
	Channel *string `json:"channel"`
	// Music is the track, when the page says the video is music (SCR-011).
	Music *BodyMusic `json:"music"`
}

// BodyMusic is a music video's track.
type BodyMusic struct {
	Artist string  `json:"artist"`
	Track  string  `json:"track"`
	Album  *string `json:"album"`
}

// BodyIDs are Trakt's ids: numbers for its numeric ids, or strings; either is read.
type BodyIDs struct {
	IMDB, TMDB, TVDB, Trakt *string
}

// UnmarshalJSON reads each id as a whole number or a string.
func (ids *BodyIDs) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	text := func(key string) (*string, error) {
		v, ok := raw[key]
		if !ok || string(v) == "null" {
			return nil, nil //nolint:nilnil // absent
		}
		var n int64
		if json.Unmarshal(v, &n) == nil {
			s := strconv.FormatInt(n, 10)
			return &s, nil
		}
		var s string
		if err := json.Unmarshal(v, &s); err != nil {
			return nil, err
		}
		return &s, nil
	}
	var err error
	if ids.IMDB, err = text("imdb"); err != nil {
		return err
	}
	if ids.TMDB, err = text("tmdb"); err != nil {
		return err
	}
	if ids.TVDB, err = text("tvdb"); err != nil {
		return err
	}
	ids.Trakt, err = text("trakt")
	return err
}

func (ids *BodyIDs) external() core.ExternalIDs {
	if ids == nil {
		return core.ExternalIDs{}
	}
	v := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	return core.ExternalIDs{TMDB: v(ids.TMDB), IMDB: v(ids.IMDB), Trakt: v(ids.Trakt), TVDB: v(ids.TVDB)}
}

// ErrNotAScrobble is a body that does not decode as a scrobble.
var ErrNotAScrobble = invalid("The body is not a scrobble.")

// ParseBody decodes a scrobble body. `source`, `ref` and `progress` are required.
func ParseBody(data []byte) (Body, error) {
	var b Body
	if err := json.Unmarshal(data, &b); err != nil {
		return Body{}, ErrNotAScrobble
	}
	var keys map[string]json.RawMessage
	if err := json.Unmarshal(data, &keys); err != nil {
		return Body{}, ErrNotAScrobble
	}
	for _, k := range []string{"source", "ref", "progress"} {
		if v, ok := keys[k]; !ok || string(v) == "null" {
			return Body{}, ErrNotAScrobble
		}
	}
	if b.Video != nil {
		var video map[string]json.RawMessage
		_ = json.Unmarshal(keys["video"], &video)
		for _, k := range []string{"id", "title"} {
			if v, ok := video[k]; !ok || string(v) == "null" {
				return Body{}, ErrNotAScrobble
			}
		}
		if b.Video.Music != nil {
			var m map[string]json.RawMessage
			_ = json.Unmarshal(video["music"], &m)
			for _, k := range []string{"artist", "track"} {
				if v, ok := m[k]; !ok || string(v) == "null" {
					return Body{}, ErrNotAScrobble
				}
			}
		}
	}
	return b, nil
}

// UnknownDurationMs: without a duration, progress is kept on a 100-second scale: only its percentage matters.
const UnknownDurationMs int64 = 100_000

func runes(s string) int { return utf8.RuneCountInString(s) }

func position(progress float64, duration int64) int64 {
	return int64(math.Round(progress / 100 * float64(duration)))
}

// Report is the playback report this body makes for action.
func (b Body) Report(action Action) (Report, error) {
	source, ok := ParseWatchSource(b.Source)
	if !ok || source == SourceStremio {
		return Report{}, invalid("source must be netflix, disney_plus or prime_video.")
	}
	if b.Ref == "" || runes(b.Ref) > 200 {
		return Report{}, invalid("ref must be 1–200 characters.")
	}
	if b.Progress < 0 || b.Progress > 100 {
		return Report{}, invalid("progress is a percentage, 0–100.")
	}
	mediaType, item, err := b.playing()
	if err != nil {
		return Report{}, err
	}
	ids := item.IDs.external()
	var name *string
	if item.Title != nil {
		n := strings.TrimSpace(*item.Title)
		name = &n
	}
	if ids.IsEmpty() && (name == nil || *name == "") {
		return Report{}, invalid("Send the title's ids or its name.")
	}
	if name != nil && runes(*name) > 300 {
		return Report{}, invalid("The title is too long.")
	}
	var key *core.EpisodeKey
	var named *catalog.NamedEpisode
	if mediaType == core.MediaShow {
		if key, named, err = b.episodeParts(); err != nil {
			return Report{}, err
		}
	}
	duration := UnknownDurationMs
	if b.DurationMs != nil && *b.DurationMs > 0 {
		duration = *b.DurationMs
	}
	return Report{
		Source: source, ExternalRef: b.Ref, Type: mediaType, IDs: ids, Episode: key, Title: name, Year: item.Year,
		EpisodeName: named, Action: action, PositionMs: position(b.Progress, duration), DurationMs: duration,
	}, nil
}

// playing is the film, or the show, this scrobble is about.
func (b Body) playing() (core.MediaType, BodyItem, error) {
	switch {
	case b.Movie != nil && b.Show == nil:
		return core.MediaMovie, *b.Movie, nil
	case b.Movie == nil && b.Show != nil:
		return core.MediaShow, *b.Show, nil
	}
	return "", BodyItem{}, invalid("Send either movie, or show with episode.")
}

// episodeParts is the episode's number when it has one, and its name when it has one; at least one.
func (b Body) episodeParts() (*core.EpisodeKey, *catalog.NamedEpisode, error) {
	e := b.Episode
	if e == nil {
		return nil, nil, invalid("A show needs its episode.")
	}
	var key *core.EpisodeKey
	if e.Season != nil && e.Number != nil {
		if k, err := core.NewEpisodeKey(*e.Season, *e.Number); err == nil {
			key = &k
		}
	}
	var named *catalog.NamedEpisode
	if e.Title != nil {
		if title := strings.TrimSpace(*e.Title); title != "" {
			named = &catalog.NamedEpisode{Season: e.Season, Name: prefix(title, 300)}
		}
	}
	if key == nil && named == nil {
		return nil, nil, invalid("An episode needs its season and number, or its title.")
	}
	return key, named, nil
}

func prefix(s string, n int) string {
	i := 0
	for pos := range s {
		if i == n {
			return s[:pos]
		}
		i++
	}
	return s
}

// VideoPlay is the video play this scrobble reports: YouTube's 11-character id, its name, and a duration.
func (b Body) VideoPlay(action Action, now time.Time) (LivePlay, error) {
	if b.Source != "youtube" || b.Video == nil || b.Movie != nil || b.Show != nil {
		return LivePlay{}, invalid("A video comes with source youtube and nothing else.")
	}
	if !music.IsYouTubeID(b.Video.ID) || b.Ref != b.Video.ID {
		return LivePlay{}, invalid("video.id is YouTube's 11-character id, and ref is the same.")
	}
	title := strings.TrimSpace(b.Video.Title)
	if title == "" || runes(title) > 300 {
		return LivePlay{}, invalid("video.title must be 1–300 characters.")
	}
	if b.Progress < 0 || b.Progress > 100 {
		return LivePlay{}, invalid("progress is a percentage, 0–100.")
	}
	if b.DurationMs == nil || *b.DurationMs <= 0 {
		return LivePlay{}, invalid("A video needs durationMs.")
	}
	duration := *b.DurationMs
	var channel *string
	if b.Video.Channel != nil {
		if c := prefix(strings.TrimSpace(*b.Video.Channel), 300); c != "" {
			channel = &c
		}
	}
	state := Playing
	if action == ActionPause {
		state = Paused
	}
	return VideoPlay(VideoReport{
		ID: b.Video.ID, Title: title, Channel: channel, State: state,
		PositionMs: position(b.Progress, duration), DurationMs: duration,
	}, now), nil
}

const (
	// HeardAfter: a listen is sent once half the track or 4 minutes has played, whichever comes first,
	// as ListenBrainz asks of every scrobbler.
	HeardAfter = 4 * time.Minute
	// ShortestListen: a video under 30 s is never one.
	ShortestListen = 30 * time.Second
)

// VideoListen is the listen a YouTube music video makes once heard (SCR-011), dated from when it began
// playing. Nil before then, and for a video the page did not say is music.
func (b Body) VideoListen(now time.Time) (*music.NewListen, error) {
	if b.Video == nil || b.Video.Music == nil || b.DurationMs == nil || *b.DurationMs <= 0 {
		return nil, nil //nolint:nilnil // not a listen
	}
	length := float64(*b.DurationMs) / 1000
	played := length * b.Progress / 100
	if length < ShortestListen.Seconds() || played < min(length/2, HeardAfter.Seconds()) {
		return nil, nil //nolint:nilnil // not heard yet
	}
	m := b.Video.Music
	artist, track := music.Text(&m.Artist), music.Text(&m.Track)
	if artist == nil || track == nil {
		return nil, invalid("video.music needs an artist and a track.")
	}
	began := math.Floor(float64(now.UnixNano())/1e9 - played)
	duration := int(*b.DurationMs)
	origin := "https://www.youtube.com/watch?v=" + b.Video.ID
	client, service := "Aaru extension", "YouTube"
	return &music.NewListen{
		ListenedAt: time.Unix(int64(began), 0), Artist: *artist, Track: *track, Album: music.Text(m.Album),
		DurationMs: &duration, OriginURL: &origin, Client: &client, MusicService: &service,
	}, nil
}

// Answer is what Aaru made of a scrobble, so the extension can say "Matched: …" or "Not matched".
type Answer struct {
	Outcome Outcome      `json:"outcome"`
	Title   *AnswerTitle `json:"title,omitempty"`
}

// AnswerTitle is the title a scrobble matched.
type AnswerTitle struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Year *int   `json:"year,omitempty"`
}

// NewAnswer names the outcome and the matched title (its id upper case, as Swift's description).
func NewAnswer(outcome Outcome, title *core.Title) Answer {
	a := Answer{Outcome: outcome}
	if title != nil {
		a.Title = &AnswerTitle{ID: strings.ToUpper(title.ID.String()), Name: title.Title, Year: title.Year}
	}
	return a
}
