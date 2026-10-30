// Package mal is MyAnimeList connect, push and read-back (MAL/*.swift; SCR-005, SCR-010): the
// one two-way exception. Anime progress goes out as the library changes (Pusher); the list comes
// back through the import merge when a client opens Aaru and every 6 hours (Puller). Worker runs
// both every 30 seconds.
//
// The API other areas call: ConnectService (the handlers), NewWorker (the background loop).
package mal

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/crypto"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/trakt"
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// MyAnimeList's hosts (MALSettings).
const (
	AuthorizeURL = "https://myanimelist.net/v1/oauth2/authorize"
	TokenURL     = "https://myanimelist.net/v1/oauth2/token" //nolint:gosec // a URL, not a credential
	APIURL       = "https://api.myanimelist.net/v2"
)

// Settings is SCR-005's configuration. MAL issues a client secret only to apps registered as
// "web"; one registered as "other" has none, and every request then goes without it.
type Settings struct {
	ClientID     string
	ClientSecret *string
	// RedirectURI must match the MAL app's App Redirect URL exactly.
	RedirectURI string
	// ReturnPrefixes are where a finished connect may send the browser.
	ReturnPrefixes []string
	Cipher         *crypto.TokenCipher
}

// NewSettings builds the settings from config (nil when MyAnimeList is not configured).
func NewSettings(p *config.OAuthProvider) (*Settings, error) {
	if p == nil {
		return nil, nil //nolint:nilnil // unset turns MyAnimeList off
	}
	cipher, err := crypto.NewTokenCipherFromKey(p.TokenKey)
	if err != nil {
		return nil, fmt.Errorf("mal token key: %w", err)
	}
	var secret *string
	if p.ClientSecret != nil && strings.TrimSpace(*p.ClientSecret) != "" {
		secret = p.ClientSecret
	}
	return &Settings{
		ClientID: p.ClientID, ClientSecret: secret, RedirectURI: p.RedirectURI.String(),
		ReturnPrefixes: p.ReturnPrefixes, Cipher: cipher,
	}, nil
}

// API is MyAnimeList's API v2 through the paced provider client. Token calls and list writes are
// form-encoded, as MAL asks; reads are JSON.
type API struct {
	Client   *provider.Client
	Settings Settings
}

// NewAPI paces MAL at one request a second across all users: MAL publishes no rate limit, and
// bursts get 403s.
func NewAPI(settings Settings, transport provider.Transport) *API {
	return &API{Client: provider.NewClient("mal", transport, provider.NewPacer(1, 3)), Settings: settings}
}

// Tokens is MAL's token answer.
type Tokens struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
}

// Exchange trades the callback's code for tokens.
func (a *API) Exchange(ctx context.Context, code, verifier string) (Tokens, error) {
	return a.token(ctx, [][2]string{
		{"grant_type", "authorization_code"},
		{"code", code},
		{"code_verifier", verifier},
		{"redirect_uri", a.Settings.RedirectURI},
	})
}

// Refresh trades the refresh token for new tokens.
func (a *API) Refresh(ctx context.Context, refreshToken string) (Tokens, error) {
	return a.token(ctx, [][2]string{{"grant_type", "refresh_token"}, {"refresh_token", refreshToken}})
}

func (a *API) token(ctx context.Context, fields [][2]string) (Tokens, error) {
	fields = append([][2]string{{"client_id", a.Settings.ClientID}}, fields...)
	if a.Settings.ClientSecret != nil {
		fields = append(fields, [2]string{"client_secret", *a.Settings.ClientSecret})
	}
	var raw struct {
		AccessToken  *string `json:"access_token"`
		RefreshToken *string `json:"refresh_token"`
		ExpiresIn    *int    `json:"expires_in"`
	}
	if err := a.Client.DecodeJSON(ctx, provider.Request{
		Method: "POST", URL: TokenURL,
		Headers: [][2]string{{"Content-Type", "application/x-www-form-urlencoded"}}, Body: Form(fields),
	}, &raw); err != nil {
		return Tokens{}, err
	}
	if raw.AccessToken == nil || raw.RefreshToken == nil || raw.ExpiresIn == nil {
		return Tokens{}, provider.NewError(a.Client.Name, provider.KindMalformed)
	}
	return Tokens{AccessToken: *raw.AccessToken, RefreshToken: *raw.RefreshToken, ExpiresIn: *raw.ExpiresIn}, nil
}

// Username is the account's MAL name.
func (a *API) Username(ctx context.Context, token string) (*string, error) {
	var user struct {
		Name *string `json:"name"`
	}
	if err := a.Client.DecodeJSON(ctx, provider.Request{URL: APIURL + "/users/@me", Headers: auth(token)}, &user); err != nil {
		return nil, err
	}
	return user.Name, nil
}

// UpdateListStatus creates or updates the user's entry for one anime. MAL answers with the entry
// as stored.
func (a *API) UpdateListStatus(ctx context.Context, malID string, state EntryState, token string) error {
	_, err := a.Client.Data(ctx, provider.Request{
		Method:  "PATCH",
		URL:     APIURL + "/anime/" + malID + "/my_list_status",
		Headers: append(auth(token), [2]string{"Content-Type", "application/x-www-form-urlencoded"}),
		Body: Form([][2]string{
			{"status", string(state.Status)},
			{"num_watched_episodes", strconv.Itoa(state.Episodes)},
			{"score", strconv.Itoa(state.Score)},
		}),
	})
	return err
}

// AnimeList is one page of the user's anime list, newest change first (SCR-010).
func (a *API) AnimeList(ctx context.Context, token string, offset, limit int) (ListPage, error) {
	url := APIURL + "/users/@me/animelist?" + trakt.QueryString([][2]string{
		{"fields", "list_status,num_episodes,media_type"},
		{"sort", "list_updated_at"},
		{"limit", strconv.Itoa(limit)},
		{"offset", strconv.Itoa(offset)},
		{"nsfw", "true"},
	})
	body, err := a.Client.Data(ctx, provider.Request{URL: url, Headers: auth(token)})
	if err != nil {
		return ListPage{}, err
	}
	page, err := DecodeListPage(body)
	if err != nil {
		return ListPage{}, provider.NewError(a.Client.Name, provider.KindMalformed)
	}
	return page, nil
}

func auth(token string) [][2]string { return [][2]string{{"Authorization", "Bearer " + token}} }

// Form encodes fields as MAL reads them: everything outside the unreserved set percent-encoded.
func Form(fields [][2]string) []byte {
	pairs := make([]string, len(fields))
	for i, f := range fields {
		pairs[i] = f[0] + "=" + formEscape(f[1])
	}
	return []byte(strings.Join(pairs, "&"))
}

func formEscape(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || strings.IndexByte("-._~", c) >= 0 {
			b.WriteByte(c)
			continue
		}
		fmt.Fprintf(&b, "%%%02X", c)
	}
	return b.String()
}

// MARK: The list (SCR-010)

// ListPage is one page of the user's anime list.
type ListPage struct {
	Data []ListEntry
	// Next is MAL's link to the next page; nil on the last.
	Next *string
}

// ListEntry is one anime on the user's list: the catalog entry and the user's status for it.
type ListEntry struct {
	Node       Node
	ListStatus ListStatusEntry
}

// Node is MAL's catalog entry.
type Node struct {
	ID          int
	Title       string
	MediaType   *string
	NumEpisodes *int
}

// ListStatusEntry is the user's status for one anime.
type ListStatusEntry struct {
	Status             *string
	Score              *int
	NumEpisodesWatched *int
	UpdatedAt          time.Time
	FinishDate         *string
}

// DecodeListPage reads a page as Swift's decoder did: `data`, each node's id and title, and each
// entry's `updated_at` are required; MAL writes `2017-11-11T19:51:22+00:00`, fractional seconds
// allowed.
func DecodeListPage(body []byte) (ListPage, error) {
	var raw struct {
		Data *[]struct {
			Node *struct {
				ID          *int    `json:"id"`
				Title       *string `json:"title"`
				MediaType   *string `json:"media_type"`
				NumEpisodes *int    `json:"num_episodes"`
			} `json:"node"`
			ListStatus *struct {
				Status             *string `json:"status"`
				Score              *int    `json:"score"`
				NumEpisodesWatched *int    `json:"num_episodes_watched"`
				UpdatedAt          *string `json:"updated_at"`
				FinishDate         *string `json:"finish_date"`
			} `json:"list_status"`
		} `json:"data"`
		Paging *struct {
			Next *string `json:"next"`
		} `json:"paging"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		return ListPage{}, err
	}
	if raw.Data == nil {
		return ListPage{}, fmt.Errorf("mal list page: no data")
	}
	page := ListPage{Data: make([]ListEntry, 0, len(*raw.Data))}
	if raw.Paging != nil {
		page.Next = raw.Paging.Next
	}
	for _, e := range *raw.Data {
		if e.Node == nil || e.Node.ID == nil || e.Node.Title == nil || e.ListStatus == nil || e.ListStatus.UpdatedAt == nil {
			return ListPage{}, fmt.Errorf("mal list page: incomplete entry")
		}
		updated, err := time.Parse(time.RFC3339Nano, *e.ListStatus.UpdatedAt)
		if err != nil {
			return ListPage{}, fmt.Errorf("mal list page: %w", err)
		}
		page.Data = append(page.Data, ListEntry{
			Node: Node{ID: *e.Node.ID, Title: *e.Node.Title, MediaType: e.Node.MediaType, NumEpisodes: e.Node.NumEpisodes},
			ListStatus: ListStatusEntry{
				Status: e.ListStatus.Status, Score: e.ListStatus.Score, NumEpisodesWatched: e.ListStatus.NumEpisodesWatched,
				UpdatedAt: updated, FinishDate: e.ListStatus.FinishDate,
			},
		})
	}
	return page, nil
}
