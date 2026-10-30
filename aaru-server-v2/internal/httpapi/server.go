// Package httpapi implements the generated `/v1` strict server (internal/api)
// plus the routes outside openapi.yaml (Stremio, MCP, scrobble, ListenBrainz,
// OAuth, the realtime socket, internal metrics). Handlers translate between the
// API's DTOs and the domain services; rules live in the services.
//
// One file per area, named after the Swift handler file it replaces
// (library.go for LibraryHandlers.swift). An area not yet ported still answers
// from its stub_*.go placeholder.
package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/billing"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/oauth"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/schedule"
	"aaru-go-api/internal/scrobble"
	"aaru-go-api/internal/sports"
	"aaru-go-api/internal/stats"
	"aaru-go-api/internal/stremio"
	"aaru-go-api/internal/telemetry"
	"aaru-go-api/internal/tonight"
	"context"
	"log/slog"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// errNotImplemented answers a route whose handler has not been ported yet.
var errNotImplemented = apperr.New(501, "not_implemented", "This route is not available yet.")

var _ api.StrictServerInterface = (*Server)(nil)

// Deps is what the handlers are built from. Each area adds its services here.
type Deps struct {
	Config *config.App
	Pool   *pgxpool.Pool
	Log    *slog.Logger

	// APNs is nil when APNS_PRIVATE_KEY is unset: devices register, nothing is sent. It also
	// sends Live Activity pushes (push.LiveActivitySender).
	APNs *push.APNSSender
	// WebPush is nil when VAPID_CONFIG is unset: the web push routes answer 503.
	WebPush push.WebSender
	// Push fans one alert out to a user's devices and browsers (never nil once built by app).
	Push *push.UserPush
	// Apple verifies App Store signed data; nil answers billing routes with 503.
	Apple billing.AppleVerifier
	// ProductEvents is nil when POSTHOG_PROJECT_TOKEN is unset; it runs as a worker to flush.
	ProductEvents *telemetry.PostHog
	// Auth is sign-in, sign-out and account deletion (auth.FromConfig).
	Auth *auth.Service
	// AgentTokens mints agent, scrobble and music tokens and authenticates them
	// for the MCP, Stremio, scrobble and ListenBrainz transports.
	AgentTokens *auth.AgentTokenService
	// OAuth is the front door for Claude's connector (oauth.FromConfig).
	OAuth *oauth.Service
	// Catalog is search, title detail, resolution, Discover and the refresh worker
	// (catalog.NewKit). Other areas resolve refs through Catalog.Resolver().
	Catalog *catalog.Kit
	// Gamification is points, streaks, badges and the board (GAM-001…005). New builds one over
	// Pool when unset. Library, social, listens, imports and plans call its hooks.
	Gamification *gamification.Service
	// Stats is Insights, the Recap and the profile's numbers (GAM-006a…e, MUS-008). New builds one
	// over Pool when unset.
	Stats *stats.Service
	// Concerts is MUS-003/MUS-010 (concerts off when its Listing is nil). New builds one with
	// concerts off when it is nil.
	Concerts *concerts.Service
	// ConcertArtists is the music catalog's album artists (MusicBrainz) for the concert
	// refresher; nil leaves albums waiting.
	ConcertArtists concerts.ArtistSource
	// Sports is SPT-001…002 (sports off when its Listing is nil). New builds one with sports
	// off when it is nil.
	Sports *sports.Service
	// Library is items, progress, the journal and undo (library.NewService); Lists and Shelves
	// sit on it. New builds them over Pool and Catalog when unset. Imports, scrobbles, plans,
	// groups, boards and invites write through Library.
	Library *library.Service
	Lists   *library.Lists
	Shelves *library.Shelves
	// Schedule is the calendar, Up Next and Watching (CAL-001, UPN-001/002, APP-018). New builds
	// one over Pool when unset.
	Schedule *schedule.Service
	// Tonight is the Tonight strip (AG-005). New builds one over Schedule when unset.
	Tonight *tonight.Service
	// Model is the agent's language model; nil when ANTHROPIC_API_KEY is unset (`@aaru` and
	// capture reading stay off).
	Model model.Provider
	// Listens is the listening log (MUS-004…008). New builds one over Pool when unset. Imports
	// stage and apply listening history through Listens.Store.
	Listens *music.Service
	// Scrobble is watch events, plays and the "Now playing" Live Activity (SCR-001…011). New
	// builds one over Pool, Library and Catalog when unset; its Notifier pushes through APNs, and
	// is nil (no Live Activity pushes) when APNs is.
	Scrobble *scrobble.Service
	// StremioSeries is Cinemeta's series lookup, which puts Stremio's episode numbers on the TMDB
	// show; nil keeps them as they come.
	StremioSeries stremio.SeriesSource
	// Stremio is the addon (SCR-003). New builds it when unset.
	Stremio *stremio.Service
}

// Server implements api.StrictServerInterface.
type Server struct {
	Deps
	q *sqlc.Queries
}

// New builds the handlers.
func New(deps Deps) *Server {
	q := sqlc.New(deps.Pool)
	if deps.Gamification == nil && deps.Pool != nil {
		deps.Gamification = gamification.New(deps.Pool, deps.Log)
	}
	if deps.Stats == nil && deps.Pool != nil {
		deps.Stats = stats.New(deps.Pool)
	}
	if deps.Concerts == nil {
		deps.Concerts = concerts.NewService(&concerts.Store{Q: q, Pool: deps.Pool}, nil, nil)
	}
	if deps.Sports == nil {
		deps.Sports = sports.NewService(&sports.Store{Q: q, Pool: deps.Pool}, nil)
	}
	if deps.Library == nil && deps.Pool != nil && deps.Catalog != nil {
		deps.Library = library.NewService(library.NewStore(deps.Pool), deps.Catalog, deps.Gamification, deps.Log)
	}
	if deps.Library != nil {
		if deps.Lists == nil {
			deps.Lists = &library.Lists{Library: deps.Library}
		}
		if deps.Shelves == nil {
			deps.Shelves = &library.Shelves{Library: deps.Library}
		}
		if deps.Library.Store.OnProgress == nil {
			// A progress write takes a Tonight pick shown in the last six hours (AG-005).
			deps.Library.Store.OnProgress = func(ctx context.Context, user uuid.UUID, items []uuid.UUID) error {
				return tonight.AcceptPicks(ctx, q, user, items)
			}
		}
	}
	if deps.Schedule == nil && deps.Pool != nil {
		deps.Schedule = schedule.New(deps.Pool)
	}
	if deps.Tonight == nil && deps.Schedule != nil {
		deps.Tonight = tonight.New(sqlc.New(deps.Pool), deps.Schedule)
	}
	if deps.Listens == nil && deps.Pool != nil {
		deps.Listens = &music.Service{Store: music.NewStore(deps.Pool), Gamification: deps.Gamification}
	}
	if deps.Scrobble == nil && deps.Pool != nil && deps.Library != nil && deps.Catalog != nil {
		deps.Scrobble = &scrobble.Service{
			Store: scrobble.NewStore(deps.Pool), Library: deps.Library, Catalog: deps.Catalog, Listens: deps.Listens,
			Log: deps.Log,
		}
		if deps.APNs != nil {
			deps.Scrobble.Notifier = &scrobble.Notifier{
				Store: deps.Scrobble.Store, Titles: deps.Catalog.Store, Sender: deps.APNs, Log: deps.Log,
			}
		}
	}
	if deps.Stremio == nil && deps.Scrobble != nil && deps.Schedule != nil {
		deps.Stremio = &stremio.Service{
			Library: deps.Library, Schedule: deps.Schedule, Catalog: deps.Catalog, Scrobble: deps.Scrobble,
		}
		if deps.StremioSeries != nil {
			deps.Stremio.EpisodeMap = stremio.NewEpisodeMap(deps.StremioSeries)
		}
	}
	return &Server{Deps: deps, q: q}
}

// currentUser is the signed-in user. The auth middleware already refused
// anonymous requests to non-public routes; this guards a route that forgot to be listed.
func currentUser(ctx context.Context) (uuid.UUID, error) {
	id, ok := reqctx.UserID(ctx)
	if !ok {
		return uuid.Nil, apperr.Unauthorized()
	}
	return id, nil
}
