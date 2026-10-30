package catalog

import (
	"aaru-go-api/internal/provider"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Kit is the catalog, built once per process: the adapters and the services other
// areas call.
type Kit struct {
	Store     *Store
	Providers Providers
	Service   *Service
	Discover  *DiscoverService
	Refresher *Refresher
	// MusicBrainz is the album adapter, also the recording matcher and the album
	// artist lister (MUS-003): one client, one pacer.
	MusicBrainz *MusicBrainz
	// ListenBrainzClient is shared by Discover's album rows and listening imports
	// (MUS-004), so both stay on ListenBrainz's one pacer.
	ListenBrainzClient *provider.Client
}

// Resolver is a fresh resolver over the kit's store and providers.
func (k *Kit) Resolver() Resolver { return NewResolver(k.Store, k.Providers) }

// NewProviders builds the adapters with the Swift server's pacing
// (makeCatalogProviders): TMDB 40/s, AniList 1.5/s burst 5 (90 a minute), Open
// Library 3/s, TVmaze 1.8/s burst 5 (~20 per 10 s), MusicBrainz 1/s, ListenBrainz
// 1/s burst 2. userAgent is the contact User-Agent the open APIs ask for.
func NewProviders(tmdbAPIKey, userAgent string, transport provider.Transport) Providers {
	musicBrainz := &MusicBrainz{
		Client:    provider.NewClient("musicbrainz", transport, provider.NewPacer(1, 1)),
		UserAgent: userAgent,
	}
	listenBrainz := provider.NewClient("listenbrainz", transport, provider.NewPacer(1, 2))
	anilistClient := provider.NewClient("anilist", transport, provider.NewPacer(1.5, 5))
	anilistClient.Classify = ClassifyAniList
	return Providers{
		TMDB:        &TMDB{Client: provider.NewClient("tmdb", transport, provider.NewPacer(40, 40)), APIKey: tmdbAPIKey},
		AniList:     &AniList{Client: anilistClient, UserAgent: userAgent},
		OpenLibrary: &OpenLibrary{Client: provider.NewClient("openlibrary", transport, provider.NewPacer(3, 3)), UserAgent: userAgent},
		AirTimes:    &TVmaze{Client: provider.NewClient("tvmaze", transport, provider.NewPacer(1.8, 5))},
		Music:       musicBrainz,
		Releases:    &ListenBrainz{Client: listenBrainz, UserAgent: userAgent},
		Recordings:  musicBrainz,
	}
}

// NewKit builds the catalog over providers. Discover reads TMDB, AniList, Open
// Library and ListenBrainz (first source wins each row), falls back to TMDB for anime
// rows while AniList is down, and times the on-air guide with TVmaze.
func NewKit(pool *pgxpool.Pool, providers Providers, log *slog.Logger) *Kit {
	store := NewStore(pool)
	service := NewService(store, providers)
	sources := []any{providers.TMDB, providers.AniList, providers.OpenLibrary}
	if providers.Releases != nil {
		sources = append(sources, providers.Releases)
	}
	var fallback DiscoverLister
	if l, ok := providers.TMDB.(DiscoverLister); ok {
		fallback = l
	}
	var timing NextEpisodeTimer
	if t, ok := providers.AirTimes.(NextEpisodeTimer); ok {
		timing = t
	}
	kit := &Kit{
		Store: store, Providers: providers, Service: service,
		Discover:  NewDiscoverService(store, sources, fallback, timing, log),
		Refresher: NewRefresher(store, service),
	}
	if mb, ok := providers.Music.(*MusicBrainz); ok {
		kit.MusicBrainz = mb
	}
	if lb, ok := providers.Releases.(*ListenBrainz); ok {
		kit.ListenBrainzClient = lb.Client
	}
	return kit
}
