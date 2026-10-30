// Package stremioapi is Stremio's account API and Cinemeta (Imports/Stremio/StremioAccount.swift,
// StremioWatched.swift, Zlib.swift) plus the episode-placing rule the history import (IMP-016)
// and the Stremio addon share (StremioEpisodeMap's static half).
//
// The account API is unofficial: it is what Stremio's own apps call. It is used once per import:
// a link code the user approves on stremio.com, one library read, then logout. No password
// reaches Aaru and the session key is never stored or logged; it lives in one request's locals.
package stremioapi

import (
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// UserAgent is sent on every call: Stremio's edge refuses requests without one.
const UserAgent = "Aaru/1.0 (+https://aaruapp.com)"

// LinkLifetime is how long a link code stays valid on Stremio's side. Pending and expired codes
// read the same there, so Aaru keeps the deadline itself.
const LinkLifetime = 5 * time.Minute

// The hosts, as Swift had them.
const (
	DefaultLinkBase     = "https://link.stremio.com"
	DefaultAPIBase      = "https://api.strem.io"
	DefaultCinemetaBase = "https://v3-cinemeta.strem.io"
)

// Account is StremioAccount: three paced clients, one per host.
type Account struct {
	// Link is `link.stremio.com`: the device-link codes.
	Link *provider.Client
	// API is `api.strem.io`: the library read and logout.
	API *provider.Client
	// Cinemeta is a show's episode list, which the watched bitfield is laid over.
	Cinemeta     *provider.Client
	LinkBase     string
	APIBase      string
	CinemetaBase string
}

// NewAccount builds the account over one transport with the Swift pacing (makeStremioAccount):
// 2/s for the link and account hosts, 5/s for Cinemeta, burst 5 each.
func NewAccount(transport provider.Transport) *Account {
	return &Account{
		Link:         provider.NewClient("stremio-link", transport, provider.NewPacer(2, 5)),
		API:          provider.NewClient("stremio", transport, provider.NewPacer(2, 5)),
		Cinemeta:     provider.NewClient("cinemeta", transport, provider.NewPacer(5, 5)),
		LinkBase:     DefaultLinkBase,
		APIBase:      DefaultAPIBase,
		CinemetaBase: DefaultCinemetaBase,
	}
}

// LinkCode is a code for the user to approve.
type LinkCode struct {
	Code string
	// Link is the page where the user approves the code.
	Link string
	// QRCode is a QR image of Link, for scanning from a phone.
	QRCode string
}

// APIError is an error Stremio's API reported in its body. 101 on a link read means "not
// approved yet".
type APIError struct {
	Code int
}

func (e *APIError) Error() string { return fmt.Sprintf("stremio api error %d", e.Code) }

// CreateLink asks Stremio for a new link code.
func (a *Account) CreateLink(ctx context.Context) (LinkCode, error) {
	var created struct {
		Code   *string `json:"code"`
		Link   *string `json:"link"`
		QRCode *string `json:"qrcode"`
	}
	if err := call(ctx, a.Link, get(a.LinkBase, "api/v2/create", url.Values{"type": {"Create"}}), &created); err != nil {
		return LinkCode{}, err
	}
	if created.Code == nil || created.Link == nil || created.QRCode == nil {
		return LinkCode{}, provider.NewError(a.Link.Name, provider.KindMalformed)
	}
	return LinkCode{Code: *created.Code, Link: *created.Link, QRCode: *created.QRCode}, nil
}

// ReadLink is the session key once the user has approved the code; nil while it is still pending.
func (a *Account) ReadLink(ctx context.Context, code string) (*string, error) {
	var approved struct {
		AuthKey *string `json:"authKey"`
	}
	err := call(ctx, a.Link, get(a.LinkBase, "api/v2/read", url.Values{"type": {"Read"}, "code": {code}}), &approved)
	if apiErr, ok := err.(*APIError); ok && apiErr.Code == 101 { //nolint:errorlint // call returns it unwrapped
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if approved.AuthKey == nil {
		return nil, provider.NewError(a.Link.Name, provider.KindMalformed)
	}
	return approved.AuthKey, nil
}

// Library is every library item, including removed ones and ones only ever played (`temp`). An
// item that does not decode is dropped, not the import.
func (a *Account) Library(ctx context.Context, authKey string) ([]LibraryItem, error) {
	var raw []json.RawMessage
	body := map[string]any{"authKey": authKey, "collection": "libraryItem", "ids": []string{}, "all": true}
	if err := call(ctx, a.API, post(a.APIBase, "api/datastoreGet", body), &raw); err != nil {
		return nil, err
	}
	items := make([]LibraryItem, 0, len(raw))
	for _, r := range raw {
		if item, ok := decodeLibraryItem(r); ok {
			items = append(items, item)
		}
	}
	return items, nil
}

// Logout ends the session the link code opened. Best effort: the import is done either way.
func (a *Account) Logout(ctx context.Context, authKey string) {
	_, _ = a.API.Data(ctx, post(a.APIBase, "api/logout", map[string]any{"type": "Logout", "authKey": authKey}))
}

// Series is a show as Cinemeta lists it.
type Series struct {
	// TVDB is TVDB's id for the show. TVDB, like TMDB, can keep as one show's season what IMDb
	// lists as a series of its own (Bleach: Thousand-Year Blood War), so this names the show
	// Aaru tracks. Empty when Cinemeta gives none.
	TVDB string
	// Videos is never nil: empty when Cinemeta does not know the show.
	Videos []Video
}

// Videos is a show's episodes in Cinemeta, which Stremio's ids (`tt…:season:episode`) come from.
// Empty when Cinemeta does not know the show.
func (a *Account) Videos(ctx context.Context, imdb string) ([]Video, error) {
	s, err := a.Series(ctx, imdb)
	return s.Videos, err
}

// Series is a show in Cinemeta: its episodes and its TVDB id. Empty when Cinemeta does not know it.
func (a *Account) Series(ctx context.Context, imdb string) (Series, error) {
	empty := Series{Videos: []Video{}}
	if !IsIMDbID(imdb, true) {
		return empty, nil
	}
	var envelope struct {
		Meta *struct {
			Videos []struct {
				ID       *string `json:"id"`
				Season   *int    `json:"season"`
				Episode  *int    `json:"episode"`
				Number   *int    `json:"number"`
				Released *string `json:"released"`
			} `json:"videos"`
			TVDBID json.RawMessage `json:"tvdb_id"`
		} `json:"meta"`
	}
	req := request(strings.TrimSuffix(a.CinemetaBase, "/")+"/meta/series/"+url.PathEscape(imdb)+".json", "GET", nil)
	if err := a.Cinemeta.DecodeJSON(ctx, req, &envelope); err != nil {
		if provider.IsNotFound(err) {
			return empty, nil
		}
		return Series{}, err
	}
	if envelope.Meta == nil {
		return empty, nil
	}
	out := Series{TVDB: lenientID(envelope.Meta.TVDBID), Videos: []Video{}}
	for _, v := range envelope.Meta.Videos {
		if v.ID == nil {
			// Swift's decoder required the id: the whole answer was malformed.
			return Series{}, provider.NewError(a.Cinemeta.Name, provider.KindMalformed)
		}
		episode := v.Episode
		if episode == nil {
			episode = v.Number // older entries number episodes here instead
		}
		if v.Season == nil || episode == nil {
			continue
		}
		var released *time.Time
		if v.Released != nil {
			released = ParseDate(*v.Released)
		}
		out.Videos = append(out.Videos, Video{ID: *v.ID, Season: *v.Season, Episode: *episode, Released: released})
	}
	return out, nil
}

// IsIMDbID is `tt` and digits. allowBare lets `tt` alone through, as Cinemeta's guard did.
func IsIMDbID(id string, allowBare bool) bool {
	rest, ok := strings.CutPrefix(id, "tt")
	if !ok || (!allowBare && rest == "") {
		return false
	}
	for _, r := range rest {
		if !unicode.IsNumber(r) {
			return false
		}
	}
	return true
}

// ParseDate reads Stremio's ISO 8601 dates, with or without fractional seconds.
func ParseDate(raw string) *time.Time {
	for _, layout := range []string{"2006-01-02T15:04:05.999999999Z07:00", time.RFC3339} {
		if t, err := time.Parse(layout, raw); err == nil {
			t = t.UTC()
			return &t
		}
	}
	return nil
}

// lenientID is an id Cinemeta writes as a number or a string; anything else reads as absent.
func lenientID(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var number int64
	if err := json.Unmarshal(raw, &number); err == nil {
		if number > 0 {
			return strconv.FormatInt(number, 10)
		}
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		if n, err := strconv.ParseInt(text, 10, 64); err == nil {
			return strconv.FormatInt(n, 10)
		}
	}
	return ""
}

// MARK: Wire

func request(rawURL, method string, body []byte) provider.Request {
	headers := [][2]string{{"User-Agent", UserAgent}, {"Accept", "application/json"}}
	if body != nil {
		headers = append(headers, [2]string{"Content-Type", "application/json"})
	}
	return provider.Request{Method: method, URL: rawURL, Headers: headers, Body: body}
}

func get(base, path string, query url.Values) provider.Request {
	// Encode sorts by key, as Swift did.
	return request(strings.TrimSuffix(base, "/")+"/"+path+"?"+query.Encode(), "GET", nil)
}

func post(base, path string, body map[string]any) provider.Request {
	data, err := json.Marshal(body)
	if err != nil {
		panic(fmt.Sprintf("stremio: encode body: %v", err)) // a map of plain values cannot fail
	}
	return request(strings.TrimSuffix(base, "/")+"/"+path, "POST", data)
}

// call decodes Stremio's `{"result": …}` or `{"error": {"code", "message"}}`, both with status
// 200. An error in the body is an *APIError, returned unwrapped.
func call(ctx context.Context, client *provider.Client, req provider.Request, out any) error {
	var envelope struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Code *int `json:"code"`
		} `json:"error"`
	}
	if err := client.DecodeJSON(ctx, req, &envelope); err != nil {
		return err
	}
	if len(envelope.Result) > 0 && string(envelope.Result) != "null" {
		if err := json.Unmarshal(envelope.Result, out); err != nil {
			return provider.NewError(client.Name, provider.KindMalformed)
		}
		return nil
	}
	code := 0
	if envelope.Error != nil && envelope.Error.Code != nil {
		code = *envelope.Error.Code
	}
	return &APIError{Code: code}
}
