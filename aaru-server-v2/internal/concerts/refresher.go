package concerts

import (
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/safe"
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

// FillAlbumArtists returns how many albums were looked up. A provider refusing one album (a 4xx)
// records it as looked up with no artists and the pass goes on (Go audit REL-006); any other
// provider failure skips it, and a few in a row end the pass (failuresToStop).
func (r *Refresher) FillAlbumArtists(ctx context.Context) (int, error) {
	if r.Artists == nil {
		return 0, nil
	}
	now := r.now()
	due, err := r.Store.AlbumsMissingArtists(ctx, r.AlbumLimit)
	if err != nil {
		return 0, err
	}
	done, inARow := 0, 0
	for _, album := range due {
		if err := ctx.Err(); err != nil {
			return done, err
		}
		found, err := r.Artists.AlbumArtists(ctx, album.MusicBrainzID)
		if refusedOne(err) {
			found, err = nil, nil
		}
		if _, isProvider := provider.AsError(err); isProvider {
			if inARow++; inARow >= failuresToStop {
				break
			}
			continue
		}
		if err != nil {
			return done, err
		}
		inARow = 0
		if err := r.Store.SaveAlbumArtists(ctx, found, album.TitleID, now); err != nil {
			return done, err
		}
		done++
	}
	return done, nil
}

// MatchArtists returns how many artists were matched or found unknown. A provider refusing one
// artist (a 4xx) records them unknown and the pass goes on. Any other provider failure, a spent
// day's call budget included, skips the artist, and a few in a row end the pass (failuresToStop).
func (r *Refresher) MatchArtists(ctx context.Context) (int, error) {
	if r.Listing == nil {
		return 0, nil
	}
	now := r.now()
	due, err := r.Store.ArtistsToMatch(ctx, now.Add(-RematchAfter), r.ArtistLimit)
	if err != nil {
		return 0, err
	}
	done, inARow := 0, 0
	for _, artist := range due {
		if err := ctx.Err(); err != nil {
			return done, err
		}
		var match *string
		if artist.MusicBrainzID != VariousArtists {
			found, err := r.Listing.Attractions(ctx, artist.Name)
			if refusedOne(err) {
				found, err = nil, nil
			}
			if _, isProvider := provider.AsError(err); isProvider {
				if inARow++; inARow >= failuresToStop {
					break
				}
				continue
			}
			if err != nil {
				return done, err
			}
			inARow = 0
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

// failuresToStop is how many provider failures in a row end a pass: that is the provider down, not
// one bad row. Fewer move on without recording anything, so one row that keeps failing never holds
// up the rest (Go audit REL-006).
const failuresToStop = 3

// refusedOne is a provider refusing this one request (404 or another 4xx that is not about the
// credential): asking again gets the same answer, so it is a miss, not an outage.
func refusedOne(err error) bool {
	pe, ok := provider.AsError(err)
	return ok && (pe.Kind == provider.KindNotFound || pe.Kind == provider.KindRefused)
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
		var albums, artists int
		err := safe.Step(func() error {
			var err error
			if albums, err = w.Refresher.FillAlbumArtists(ctx); err != nil {
				return err
			}
			artists, err = w.Refresher.MatchArtists(ctx)
			return err
		})
		if ctx.Err() == nil {
			metrics.WorkerPass(w.Name(), err)
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
