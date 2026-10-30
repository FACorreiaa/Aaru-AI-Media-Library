package music

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/stats"
	"context"
	"errors"
	"log/slog"
	"math"
	"time"

	"github.com/google/uuid"
)

// Service is ListenService (MUS-005): scrobblers add listens; the signed-in user reads them back as
// recent listens and top lists. A listen never touches the library.
type Service struct {
	Store *Store
	// Gamification earns a live listen's points; nil earns none.
	Gamification *gamification.Service
	// Now defaults to time.Now.
	Now func() time.Time
}

func (s *Service) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

// Submit keeps each listen unless it repeats one already stored. Returns how many were kept.
func (s *Service) Submit(ctx context.Context, listens []NewListen, caller auth.AgentCaller) (int, error) {
	id := caller.Token.ID
	kept, err := s.Store.Insert(ctx, listens, caller.UserID, &id)
	if err != nil {
		return 0, err
	}
	if kept > 0 && s.Gamification != nil {
		awarded := make([]gamification.Listen, len(listens))
		for i, l := range listens {
			awarded[i] = gamification.Listen{ListenedAt: l.ListenedAt, Artist: l.Artist, Track: l.Track}
		}
		s.Gamification.ListensKept(ctx, caller.UserID, awarded)
	}
	return kept, nil
}

// PageSize is a page's size: 20 unless asked, never more than 100.
func PageSize(limit *int) int {
	n := 20
	if limit != nil {
		n = *limit
	}
	return min(max(n, 1), 100)
}

// Listens is newest first, a page at a time.
func (s *Service) Listens(ctx context.Context, user uuid.UUID, before *time.Time, limit *int) ([]Listen, error) {
	return s.Store.Listens(ctx, user, before, int64(PageSize(limit)))
}

// All is every listen, newest first, for the account export.
func (s *Service) All(ctx context.Context, user uuid.UUID) ([]Listen, error) {
	return s.Store.Listens(ctx, user, nil, math.MaxInt64)
}

// Period is a period read the way `/v1/me/stats` reads it: a year, a month of it, or a span.
func (s *Service) Period(span *stats.Span, year, month *int, timeZone *string) (stats.Period, error) {
	return stats.PeriodFor(span, year, month, timeZone, s.now())
}

// Top is the period's top artists, tracks or albums: 10 unless asked, never more than 50. artist
// narrows it to one artist.
func (s *Service) Top(ctx context.Context, user uuid.UUID, by Grouping, period stats.Period, limit *int, artist *string) (Top, error) {
	n := 10
	if limit != nil {
		n = *limit
	}
	return s.Store.Top(ctx, user, by, period, min(max(n, 1), 50), artist)
}

// MARK: MUS-006

// RetryAfter is how long a track MusicBrainz could not place waits before it is asked again: it may
// have been added.
const RetryAfter = 30 * 24 * time.Hour

// Resolver is ListenResolver (MUS-006): identifies scrobbled tracks on MusicBrainz, each track and
// album once, so listens gain their album's cover and a link to the album. Listens keep their own
// spelling; only ids are filled, and never over ids a scrobbler sent.
type Resolver struct {
	Store      *Store
	Recordings catalog.RecordingMatcher
	// PassLimit is tracks per pass (30 when 0): each is one MusicBrainz request at one a second,
	// shared with album search.
	PassLimit int
	Now       func() time.Time
}

// RunOnce looks up one batch. Returns how many tracks were asked about and how many listens gained
// an album. A provider failure ends the pass without recording a miss.
func (r *Resolver) RunOnce(ctx context.Context) (tracks, listens int, err error) {
	now := time.Now()
	if r.Now != nil {
		now = r.Now()
	}
	limit := r.PassLimit
	if limit == 0 {
		limit = 30
	}
	due, err := r.Store.Unresolved(ctx, now.Add(-RetryAfter), limit)
	if err != nil {
		return 0, 0, err
	}
	for _, lookup := range due {
		if err := ctx.Err(); err != nil {
			return 0, listens, err
		}
		match, err := r.Recordings.Match(ctx, lookup.Query)
		if err != nil {
			return 0, listens, err
		}
		filled, err := r.Store.Resolve(ctx, lookup, match, now)
		if err != nil {
			return 0, listens, err
		}
		listens += filled
	}
	return len(due), listens, nil
}

// ResolverWorker runs the resolver every minute in the API process (ListenResolverService).
type ResolverWorker struct {
	Resolver *Resolver
	Log      *slog.Logger
	// Interval defaults to a minute.
	Interval time.Duration
}

// Name names the worker in logs.
func (w *ResolverWorker) Name() string { return "listen-resolver" }

// Run passes until ctx is cancelled.
func (w *ResolverWorker) Run(ctx context.Context) error {
	interval := w.Interval
	if interval == 0 {
		interval = time.Minute
	}
	log := w.Log
	if log == nil {
		log = slog.Default()
	}
	for {
		tracks, listens, err := w.Resolver.RunOnce(ctx)
		switch {
		case errors.Is(err, context.Canceled) || ctx.Err() != nil:
			return nil
		case err != nil:
			log.Error("Listen lookup pass failed", "error", err.Error())
		case tracks > 0:
			log.Info("Listens looked up", "tracks", tracks, "listens", listens)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(interval):
		}
	}
}
