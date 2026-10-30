package imports

// MUS-004 · a service's public listening history, read by username
// (Imports/Listens/ListenHistoryReaders.swift).

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"encoding/json"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ListenHistoryReader reads a service's public listening history by username (ListenHistoryReading).
type ListenHistoryReader interface {
	// Read reads user's plays newest first, back to since (exclusive) or the beginning, a page at a
	// time. An unknown user is a provider error of KindNotFound.
	Read(ctx context.Context, user string, since *time.Time, now time.Time, page func(ListenHistoryPage) error) error
}

// NewListenHistory is one reader per service, built at boot (makeListenHistory): ListenBrainz on the
// Discover rows' client, so both share its pacer, and Last.fm only with `LASTFM_API_KEY`.
// listenBrainz nil leaves ListenBrainz out.
func NewListenHistory(lastFMAPIKey *string, userAgent string, listenBrainz *provider.Client, transport provider.Transport) map[core.ImportSource]ListenHistoryReader {
	readers := map[core.ImportSource]ListenHistoryReader{}
	if listenBrainz != nil {
		readers[core.SourceListenBrainz] = &ListenBrainzHistory{Client: listenBrainz, UserAgent: userAgent}
	}
	if lastFMAPIKey != nil {
		// Last.fm asks for at most 5 requests a second, averaged over 5 minutes.
		readers[core.SourceLastFM] = &LastFMHistory{
			Client: NewLastFMClient(transport, provider.NewPacer(4, 4)), APIKey: *lastFMAPIKey, UserAgent: userAgent,
		}
	}
	return readers
}

// MARK: Last.fm

// LastFMBaseURL is Last.fm's API root.
const LastFMBaseURL = "https://ws.audioscrobbler.com/2.0/"

const (
	lastFMPageSize = 200
	// LastFMPrivateListening is Last.fm's error for a user who hides their recent listening. It is
	// the Status of the KindRefused provider error the reader returns for it.
	LastFMPrivateListening = 17
)

// LastFMHistory is Last.fm's `user.getRecentTracks`, 200 scrobbles a page, with an API key
// (`LASTFM_API_KEY`). The range is fixed when the read starts, so scrobbles arriving meanwhile do
// not shift the pages.
type LastFMHistory struct {
	Client    *provider.Client
	APIKey    string
	UserAgent string
	// BaseURL defaults to LastFMBaseURL.
	BaseURL string
}

// NewLastFMClient is the Last.fm client: Last.fm's own error codes are read before the status code
// (LastFMHistory.classify).
func NewLastFMClient(transport provider.Transport, pacer *provider.Pacer) *provider.Client {
	return provider.NewClient("lastfm", lastFMTransport{next: transport}, pacer)
}

// lastFMTransport hands an answer carrying a Last.fm error code to the reader as it is, whatever
// its status, so the reader maps the code (Swift's classify ran before the status-code rules and
// kept the code, which provider.Client's Classify cannot: 17 must reach the import as itself).
type lastFMTransport struct{ next provider.Transport }

func (t lastFMTransport) Send(ctx context.Context, req provider.Request) (*provider.Response, error) {
	resp, err := t.next.Send(ctx, req)
	if err != nil || resp.Status < 300 {
		return resp, err
	}
	if _, ok := lastFMErrorCode(resp.Body); ok {
		answered := *resp
		answered.Status = 200
		return &answered, nil
	}
	return resp, nil
}

func (h *LastFMHistory) Read(ctx context.Context, user string, since *time.Time, now time.Time, page func(ListenHistoryPage) error) error {
	until := now.Unix()
	pages := 1
	for number := 1; number <= pages; number++ {
		query := map[string]string{
			"method": "user.getrecenttracks", "user": user, "api_key": h.APIKey, "format": "json",
			"limit": strconv.Itoa(lastFMPageSize), "page": strconv.Itoa(number), "to": strconv.FormatInt(until, 10),
		}
		if since != nil {
			query["from"] = strconv.FormatInt(since.Unix()+1, 10)
		}
		body, err := h.get(ctx, query)
		if err != nil {
			return err
		}
		pages = 1
		if body.RecentTracks.Attr != nil && body.RecentTracks.Attr.TotalPages != nil {
			if n, err := strconv.Atoi(*body.RecentTracks.Attr.TotalPages); err == nil {
				pages = n
			}
		}
		if err := page(lastFMPage(body.RecentTracks.Tracks, now)); err != nil {
			return err
		}
	}
	return nil
}

// lastFMPage is a page's scrobbles. The track playing now has no time yet and is not a scrobble.
func lastFMPage(tracks []lastFMTrack, now time.Time) ListenHistoryPage {
	var page ListenHistoryPage
	for _, track := range tracks {
		if track.Attr != nil && track.Attr.NowPlaying != nil && *track.Attr.NowPlaying == "true" {
			continue
		}
		var playedAt *time.Time
		if track.Date != nil && track.Date.UTS != nil {
			if seconds, err := strconv.ParseFloat(*track.Date.UTS, 64); err == nil {
				t := time.Unix(0, int64(seconds*1e9)).UTC()
				playedAt = &t
			}
		}
		var artist, album *string
		var artistMBID, albumMBID *string
		if track.Artist != nil {
			artist, artistMBID = listenText(track.Artist.Text), track.Artist.MBID
		}
		if track.Album != nil {
			album, albumMBID = listenText(track.Album.Text), track.Album.MBID
		}
		name := listenText(track.Name)
		if playedAt == nil || !plausibleListenTime(*playedAt, now) || artist == nil || name == nil {
			page.Ignored++
			continue
		}
		client := "Last.fm"
		page.Listens = append(page.Listens, NewListen{
			ListenedAt: *playedAt, Artist: *artist, Track: *name, Album: album,
			RecordingMBID: listenMBID(track.MBID), ReleaseMBID: listenMBID(albumMBID),
			ArtistMBID: listenMBID(artistMBID), Client: &client,
		})
	}
	return page
}

func (h *LastFMHistory) get(ctx context.Context, query map[string]string) (*lastFMPageBody, error) {
	keys := make([]string, 0, len(query))
	for k := range query {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, url.QueryEscape(k)+"="+url.QueryEscape(query[k]))
	}
	data, err := h.Client.Data(ctx, provider.Request{
		URL:     cmp.Or(h.BaseURL, LastFMBaseURL) + "?" + strings.Join(parts, "&"),
		Headers: [][2]string{{"User-Agent", h.UserAgent}, {"Accept", "application/json"}},
	})
	if err != nil {
		return nil, err
	}
	// Last.fm can answer an error with a 200.
	if code, ok := lastFMErrorCode(data); ok {
		return nil, lastFMError(code)
	}
	var body lastFMPageBody
	if err := json.Unmarshal(data, &body); err != nil || body.RecentTracks == nil {
		return nil, provider.NewError("lastfm", provider.KindMalformed)
	}
	return &body, nil
}

// lastFMError is Last.fm's own error code as a provider error: 6 is an unknown user, 17 a private
// one; anything else (29 over the rate limit, a bad key: 10, 26) is Aaru's, not the person's: an
// outage.
func lastFMError(code int) *provider.Error {
	switch code {
	case 6:
		return provider.NewError("lastfm", provider.KindNotFound)
	case LastFMPrivateListening:
		return &provider.Error{Provider: "lastfm", Kind: provider.KindRefused, Status: LastFMPrivateListening}
	}
	return provider.NewError("lastfm", provider.KindUnavailable)
}

func lastFMErrorCode(data []byte) (int, bool) {
	var failure struct {
		Error *int `json:"error"`
	}
	if json.Unmarshal(data, &failure) != nil || failure.Error == nil {
		return 0, false
	}
	return *failure.Error, true
}

// IsLastFMPrivate is err Last.fm refusing a user who hides their recent listening.
func IsLastFMPrivate(err error) bool {
	p, ok := provider.AsError(err)
	return ok && p.Provider == "lastfm" && p.Kind == provider.KindRefused && p.Status == LastFMPrivateListening
}

// MARK: Last.fm wire shapes

// lastFMPageBody is one `user.getRecentTracks` page.
type lastFMPageBody struct {
	RecentTracks *lastFMRecentTracks `json:"recenttracks"`
}

type lastFMRecentTracks struct {
	Tracks []lastFMTrack
	Attr   *struct {
		TotalPages *string `json:"totalPages"`
	}
}

func (r *lastFMRecentTracks) UnmarshalJSON(data []byte) error {
	var raw struct {
		Track json.RawMessage `json:"track"`
		Attr  json.RawMessage `json:"@attr"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err //nolint:wrapcheck // decoding
	}
	// One scrobble comes as an object, not a list of one.
	var list []lastFMTrack
	var one lastFMTrack
	switch {
	case len(raw.Track) > 0 && json.Unmarshal(raw.Track, &list) == nil && list != nil:
		r.Tracks = list
	case len(raw.Track) > 0 && string(raw.Track) != "null" && json.Unmarshal(raw.Track, &one) == nil:
		r.Tracks = []lastFMTrack{one}
	}
	if len(raw.Attr) > 0 {
		var attr struct {
			TotalPages *string `json:"totalPages"`
		}
		if json.Unmarshal(raw.Attr, &attr) == nil {
			r.Attr = &struct {
				TotalPages *string `json:"totalPages"`
			}{attr.TotalPages}
		}
	}
	return nil
}

// lastFMNamed is a named thing on Last.fm: an artist or an album, with its MusicBrainz id when known.
type lastFMNamed struct {
	MBID *string `json:"mbid"`
	Text *string `json:"#text"`
}

type lastFMTrack struct {
	Name   *string      `json:"name"`
	MBID   *string      `json:"mbid"`
	Artist *lastFMNamed `json:"artist"`
	Album  *lastFMNamed `json:"album"`
	Date   *struct {
		UTS *string `json:"uts"`
	} `json:"date"`
	Attr *struct {
		NowPlaying *string `json:"nowplaying"`
	} `json:"@attr"`
}

// MARK: ListenBrainz

const listenBrainzHistoryPageSize = 1000

// ListenBrainzHistory is ListenBrainz's `GET /1/user/{name}/listens`, 1,000 a page, older pages
// asked by `max_ts`. It shares the Discover rows' client, and so their one-a-second pacer.
type ListenBrainzHistory struct {
	Client    *provider.Client
	UserAgent string
	// BaseURL defaults to catalog.ListenBrainzBaseURL.
	BaseURL string
}

func (h *ListenBrainzHistory) Read(ctx context.Context, user string, since *time.Time, now time.Time, page func(ListenHistoryPage) error) error {
	base := cmp.Or(h.BaseURL, catalog.ListenBrainzBaseURL) + "/user/" + listenBrainzPathEscape(user) + "/listens"
	// `max_ts` and `min_ts` are both exclusive.
	floor := ""
	if since != nil {
		floor = "&min_ts=" + strconv.FormatInt(since.Unix(), 10)
	}
	before := now.Unix() + 1
	for {
		data, err := h.Client.Data(ctx, provider.Request{
			URL: base + "?count=" + strconv.Itoa(listenBrainzHistoryPageSize) + "&max_ts=" +
				strconv.FormatInt(before, 10) + floor,
			Headers: [][2]string{{"User-Agent", h.UserAgent}, {"Accept", "application/json"}},
		})
		if err != nil {
			return err
		}
		read, oldest, err := listenBrainzHistoryPage(data, now)
		if err != nil {
			return provider.NewError("listenbrainz", provider.KindMalformed)
		}
		// An empty page is the end; a page not older than the last would never end.
		if oldest == nil || *oldest >= before {
			return nil
		}
		if err := page(read); err != nil {
			return err
		}
		before = *oldest
	}
}

// listenBrainzPathEscape keeps letters, digits and `-._~` as they are in the path and escapes
// anything else.
func listenBrainzPathEscape(name string) string {
	var b strings.Builder
	for _, c := range []byte(name) {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '-', c == '.', c == '_', c == '~':
			b.WriteByte(c)
		default:
			b.WriteString("%" + strings.ToUpper(strconv.FormatInt(int64(c)|0x100, 16)[1:]))
		}
	}
	return b.String()
}
