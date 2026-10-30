package concerts

import (
	"aaru-go-api/internal/provider"
	"context"
	"errors"
	"log/slog"
	"slices"
	"time"
)

// Refresher is MUS-003's ConcertRefresher: keeps "Your artists on tour" answerable without
// asking per request. Each pass looks up the artists of albums nobody has looked up
// (MusicBrainz), then asks the concert provider about artists never matched or matched over a
// month ago. An artist matches only when the provider's performer carries the same MusicBrainz
// id; a name alone never does.
type Refresher struct {
	Store *Store
	// Artists is nil until the music catalog is wired: albums then wait.
	Artists ArtistSource
	// Listing is nil when concerts are off: artists then wait.
	Listing Listing
	// AlbumLimit: MusicBrainz allows one call a second, shared with search.
	AlbumLimit int
	// ArtistLimit: each artist costs one provider call; 20 a pass every half hour stays far
	// inside the budget.
	ArtistLimit int
	Now         func() time.Time
}

const (
	// RematchAfter is how long a matched (or unknown) artist waits before it is asked again.
	RematchAfter = 30 * 24 * time.Hour
	// VariousArtists is MusicBrainz's "Various Artists": credited on compilations, never on a stage.
	VariousArtists = "89ad4ac3-39f7-470e-963a-56509c546377"
)

// NewRefresher has the Swift defaults: 30 albums and 20 artists a pass.
func NewRefresher(store *Store, artists ArtistSource, listing Listing) *Refresher {
	return &Refresher{Store: store, Artists: artists, Listing: listing, AlbumLimit: 30, ArtistLimit: 20, Now: time.Now}
}

func (r *Refresher) now() time.Time {
	if r.Now == nil {
		return time.Now()
	}
	return r.Now()
}

// FillAlbumArtists returns how many albums were looked up. A provider failure ends the pass;
// the rest wait.
func (r *Refresher) FillAlbumArtists(ctx context.Context) (int, error) {
	if r.Artists == nil {
		return 0, nil
	}
	now := r.now()
	due, err := r.Store.AlbumsMissingArtists(ctx, r.AlbumLimit)
	if err != nil {
		return 0, err
	}
	done := 0
	for _, album := range due {
		if err := ctx.Err(); err != nil {
			return done, err
		}
		found, err := r.Artists.AlbumArtists(ctx, album.MusicBrainzID)
		if _, isProvider := provider.AsError(err); isProvider {
			break
		}
		if err != nil {
			return done, err
		}
		if err := r.Store.SaveAlbumArtists(ctx, found, album.TitleID, now); err != nil {
			return done, err
		}
		done++
	}
	return done, nil
}

// MatchArtists returns how many artists were matched or found unknown. Stops when the provider
// fails or the day's call budget is spent.
func (r *Refresher) MatchArtists(ctx context.Context) (int, error) {
	if r.Listing == nil {
		return 0, nil
	}
	now := r.now()
	due, err := r.Store.ArtistsToMatch(ctx, now.Add(-RematchAfter), r.ArtistLimit)
	if err != nil {
		return 0, err
	}
	done := 0
	for _, artist := range due {
		if err := ctx.Err(); err != nil {
			return done, err
		}
		var match *string
		if artist.MusicBrainzID != VariousArtists {
			found, err := r.Listing.Attractions(ctx, artist.Name)
			if _, isProvider := provider.AsError(err); isProvider {
				break
			}
			if err != nil {
				return done, err
			}
			for _, a := range found {
				if slices.Contains(a.MusicBrainzIDs, artist.MusicBrainzID) {
					id := a.ID
					match = &id
					break
				}
			}
		}
		if err := r.Store.SaveMatch(ctx, artist.MusicBrainzID, match, now); err != nil {
			return done, err
		}
		done++
	}
	return done, nil
}

// Worker runs the refresher every half hour in the API process (ConcertRefreshService).
type Worker struct {
	Refresher *Refresher
	Log       *slog.Logger
	Interval  time.Duration
}

// Name is the worker's log name.
func (w *Worker) Name() string { return "concert-refresh" }

// Run passes until ctx is cancelled. A failed pass is logged and retried next interval.
func (w *Worker) Run(ctx context.Context) error {
	interval := w.Interval
	if interval <= 0 {
		interval = 30 * time.Minute
	}
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for ctx.Err() == nil {
		albums, err := w.Refresher.FillAlbumArtists(ctx)
		artists := 0
		if err == nil {
			artists, err = w.Refresher.MatchArtists(ctx)
		}
		switch {
		case errors.Is(err, context.Canceled) || ctx.Err() != nil:
			return nil
		case err != nil:
			log.Error("Concert artist pass failed", "error", err.Error())
		case albums+artists > 0:
			log.Info("Concert artists refreshed", "albums", albums, "artists", artists)
		}
		if err := provider.Sleep(ctx, interval); err != nil {
			return nil
		}
	}
	return nil
}
