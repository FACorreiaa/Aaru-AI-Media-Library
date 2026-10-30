package trakt

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"strconv"
	"time"
)

// API is Trakt's API through the paced provider client (TraktAPI). PKCE only: no request carries
// a client secret, because Trakt issues none to this app.
type API struct {
	Client   *provider.Client
	Settings Settings
}

// NewAPI paces Trakt under its 500 reads per 5 minutes per user (1.67/s).
func NewAPI(settings Settings, transport provider.Transport) *API {
	return &API{Client: provider.NewClient("trakt", transport, provider.NewPacer(1.5, 10)), Settings: settings}
}

// Tokens is Trakt's token answer.
type Tokens struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
	CreatedAt    int
}

// Exchange trades the callback's code for tokens.
func (a *API) Exchange(ctx context.Context, code, verifier string) (Tokens, error) {
	return a.token(ctx, map[string]string{
		"code": code, "client_id": a.Settings.ClientID, "redirect_uri": a.Settings.RedirectURI,
		"grant_type": "authorization_code", "code_verifier": verifier,
	})
}

// Refresh spends the single-use refresh token for new tokens.
func (a *API) Refresh(ctx context.Context, refreshToken string) (Tokens, error) {
	return a.token(ctx, map[string]string{
		"refresh_token": refreshToken, "client_id": a.Settings.ClientID,
		"redirect_uri": a.Settings.RedirectURI, "grant_type": "refresh_token",
	})
}

func (a *API) token(ctx context.Context, body map[string]string) (Tokens, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return Tokens{}, err
	}
	var raw struct {
		AccessToken  *string `json:"access_token"`
		RefreshToken *string `json:"refresh_token"`
		ExpiresIn    *int    `json:"expires_in"`
		CreatedAt    *int    `json:"created_at"`
	}
	if err := a.Client.DecodeJSON(ctx, provider.Request{
		Method: "POST", URL: AuthURL + "/oauth/token", Headers: a.headers(nil), Body: data,
	}, &raw); err != nil {
		return Tokens{}, err
	}
	if raw.AccessToken == nil || raw.RefreshToken == nil || raw.ExpiresIn == nil || raw.CreatedAt == nil {
		return Tokens{}, provider.NewError(a.Client.Name, provider.KindMalformed)
	}
	return Tokens{AccessToken: *raw.AccessToken, RefreshToken: *raw.RefreshToken, ExpiresIn: *raw.ExpiresIn, CreatedAt: *raw.CreatedAt}, nil
}

// Revoke ends this app's access on the user's Trakt account, which frees one of their app slots.
func (a *API) Revoke(ctx context.Context, accessToken string) error {
	data, err := json.Marshal(map[string]string{"token": accessToken, "client_id": a.Settings.ClientID})
	if err != nil {
		return err
	}
	_, err = a.Client.Data(ctx, provider.Request{
		Method: "POST", URL: AuthURL + "/oauth/revoke", Headers: a.headers(nil), Body: data,
	})
	return err
}

// Username is the account's Trakt username, if it has one.
func (a *API) Username(ctx context.Context, token string) (*string, error) {
	var settings struct {
		User *struct {
			Username *string `json:"username"`
		} `json:"user"`
	}
	if err := a.Client.DecodeJSON(ctx, a.request("users/settings", nil, token), &settings); err != nil {
		return nil, err
	}
	if settings.User == nil {
		return nil, nil //nolint:nilnil // no user
	}
	return settings.User.Username, nil
}

// PageSize is the most items Trakt allows per page; a larger `limit` is silently capped.
const PageSize = 250

// MaxPages is a runaway guard: 400 pages of 250 is 100,000 items of one kind.
const MaxPages = 400

// paged reads every page of a list. Trakt pages lists, watchlists, ratings and watched (and without
// `page`/`limit` returns only the first 10–100 items), and may send fewer items than asked. An
// endpoint that does not page sends no `X-Pagination-Page-Count`: one call has it all.
func paged[T any](ctx context.Context, a *API, path string, query [][2]string, token string, valid func(T) bool) ([]T, error) {
	var items []T
	for page := 1; page <= MaxPages; page++ {
		q := append(append([][2]string{}, query...), [2]string{"page", strconv.Itoa(page)}, [2]string{"limit", strconv.Itoa(PageSize)})
		resp, err := a.Client.Do(ctx, a.request(path, q, token))
		if err != nil {
			return nil, err
		}
		var batch []T
		if err := json.Unmarshal(resp.Body, &batch); err != nil || batch == nil {
			return nil, provider.NewError(a.Client.Name, provider.KindMalformed)
		}
		for _, item := range batch {
			if !valid(item) {
				return nil, provider.NewError(a.Client.Name, provider.KindMalformed)
			}
		}
		items = append(items, batch...)
		pages, convErr := strconv.Atoi(resp.HeaderValue("X-Pagination-Page-Count"))
		if len(batch) == 0 || convErr != nil || page >= pages {
			break
		}
	}
	return items, nil
}

func (a *API) request(path string, query [][2]string, token string) provider.Request {
	url := APIURL + "/" + path
	if len(query) > 0 {
		url += "?" + QueryString(query)
	}
	return provider.Request{URL: url, Headers: a.headers(&token), Timeout: 30 * time.Second}
}

// headers are what Trakt asks of every call; the bearer token only on the user's own data.
func (a *API) headers(token *string) [][2]string {
	headers := [][2]string{
		{"Content-Type", "application/json"},
		{"User-Agent", UserAgent},
		{"trakt-api-version", "2"},
		{"trakt-api-key", a.Settings.ClientID},
	}
	if token != nil {
		headers = append(headers, [2]string{"Authorization", "Bearer " + *token})
	}
	return headers
}

// MARK: Trakt's shapes (only what the import reads)

// IDs are a Trakt entry's ids.
type IDs struct {
	Trakt *int    `json:"trakt"`
	IMDB  *string `json:"imdb"`
	TMDB  *int    `json:"tmdb"`
	TVDB  *int    `json:"tvdb"`
}

// ExternalIDs are the ids as Aaru keeps them.
func (i IDs) ExternalIDs() core.ExternalIDs {
	str := func(n *int) string {
		if n == nil {
			return ""
		}
		return strconv.Itoa(*n)
	}
	ids := core.ExternalIDs{TMDB: str(i.TMDB), Trakt: str(i.Trakt), TVDB: str(i.TVDB)}
	if i.IMDB != nil {
		ids.IMDB = *i.IMDB
	}
	return ids
}

// Media is a movie or show.
type Media struct {
	Title *string `json:"title"`
	Year  *int    `json:"year"`
	IDs   *IDs    `json:"ids"`
}

func validMedia(m *Media) bool { return m != nil && m.IDs != nil }

// WatchedMovie is one entry of the watched movies.
type WatchedMovie struct {
	LastWatchedAt *string `json:"last_watched_at"`
	Movie         *Media  `json:"movie"`
}

// WatchedShow is one entry of the watched shows, with seasons when asked for progress.
type WatchedShow struct {
	LastWatchedAt *string  `json:"last_watched_at"`
	Show          *Media   `json:"show"`
	Seasons       []Season `json:"seasons"`
}

// Season is a watched season.
type Season struct {
	Number   *int `json:"number"`
	Episodes []struct {
		Number *int `json:"number"`
	} `json:"episodes"`
}

func validSeasons(seasons []Season) bool {
	for _, s := range seasons {
		if s.Number == nil || s.Episodes == nil {
			return false
		}
		for _, e := range s.Episodes {
			if e.Number == nil {
				return false
			}
		}
	}
	return true
}

// Item is a watchlist, rating or list entry: one of movie or show (episodes and seasons are skipped).
type Item struct {
	Type   *string `json:"type"`
	Rating *int    `json:"rating"`
	Movie  *Media  `json:"movie"`
	Show   *Media  `json:"show"`
}

func validItem(i Item) bool {
	return i.Type != nil && (i.Movie == nil || validMedia(i.Movie)) && (i.Show == nil || validMedia(i.Show))
}

// List is one of the user's lists.
type List struct {
	Name *string `json:"name"`
	IDs  *struct {
		Trakt *int `json:"trakt"`
	} `json:"ids"`
}
