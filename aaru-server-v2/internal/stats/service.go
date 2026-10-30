package stats

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// The years a calendar period may ask for.
const (
	MinYear = 1900
	MaxYear = 2200
)

// Service is StatsService: period stats and the profile's numbers.
type Service struct {
	pool   *pgxpool.Pool
	q      *sqlc.Queries
	titles *catalog.Store
	// Now is the clock; nil is time.Now.
	Now func() time.Time
}

// New builds the service over the pool.
func New(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool, q: sqlc.New(pool), titles: catalog.NewStore(pool)}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

const zoneMessage = "Use an IANA time zone such as Europe/Lisbon."

// loadZone is TimeZone(identifier:) over an absent zone meaning UTC.
func loadZone(identifier *string) (*time.Location, bool) {
	name := "UTC"
	if identifier != nil {
		name = *identifier
	}
	if name == "" || name == "Local" || len(name) > 64 {
		return nil, false
	}
	loc, err := time.LoadLocation(name)
	return loc, err == nil
}

func invalid(details map[string]string) *apperr.Error {
	values := make([]string, 0, len(details))
	for _, v := range details {
		values = append(values, v)
	}
	slices.Sort(values)
	return apperr.New(http.StatusUnprocessableEntity, "validation_failed", strings.Join(values, " ")).WithDetails(details)
}

// PeriodFor is GAM-006c/d: a year, a month of it, all time up to today, or the last 7 or 30 days
// ending today, in the user's time zone. A span takes no year or month; otherwise a year is
// required.
func PeriodFor(span *Span, year, month *int, timeZone *string, now time.Time) (Period, error) {
	if span != nil {
		if *span != SpanAll && span.Days() == 0 {
			return Period{}, invalid(map[string]string{"span": "Use all, last7 or last30."})
		}
		if year != nil || month != nil {
			msg := "A rolling span takes no year or month."
			if *span == SpanAll {
				msg = "All time takes no year or month."
			}
			return Period{}, invalid(map[string]string{"span": msg})
		}
		zone, ok := loadZone(timeZone)
		if !ok {
			return Period{}, invalid(map[string]string{"tz": zoneMessage})
		}
		today := DayOf(now, zone)
		if *span == SpanAll {
			return AllTimeUntil(today, zone), nil
		}
		return LastDays(*span, today, zone), nil
	}
	if year == nil {
		return Period{}, invalid(map[string]string{"year": "Send a year, or a span."})
	}
	return CalendarPeriodFor(*year, month, timeZone)
}

// CalendarPeriodFor validates a year, an optional month and a zone together.
func CalendarPeriodFor(year int, month *int, timeZone *string) (Period, error) {
	details := map[string]string{}
	if year < MinYear || year > MaxYear {
		details["year"] = fmt.Sprintf("Use a year between %d and %d.", MinYear, MaxYear)
	}
	if month != nil && (*month < 1 || *month > 12) {
		details["month"] = "Use a month from 1 to 12."
	}
	zone, ok := loadZone(timeZone)
	if !ok {
		details["tz"] = zoneMessage
	}
	if len(details) > 0 {
		return Period{}, invalid(details)
	}
	return CalendarPeriod(year, month, zone), nil
}

// Stats is the period's stats (GAM-006a/c/d/e) with its listening (MUS-008).
func (s *Service) Stats(ctx context.Context, userID uuid.UUID, span *Span, year, month *int, timeZone *string) (PeriodStats, error) {
	now := s.now()
	period, err := PeriodFor(span, year, month, timeZone, now)
	if err != nil {
		return PeriodStats{}, err
	}
	today := DayOf(now, period.TimeZone)
	// A rolling window reads its previous window in the same query, for the deltas.
	previous := period.Previous()
	from := period.Start
	if previous != nil {
		from = previous.Start
	}
	rows, err := s.Activity(ctx, userID, from, period.End, period.TimeZone)
	if err != nil {
		return PeriodStats{}, err
	}
	if period.Span == SpanAll && len(rows) > 0 {
		first := rows[0].Day.Year
		for _, r := range rows {
			first = min(first, r.Day.Year)
		}
		period.FirstYear = min(first, period.Year)
	}
	var current, before []Activity
	for _, r := range rows {
		if r.Day.Less(period.Start) {
			before = append(before, r)
		} else {
			current = append(current, r)
		}
	}
	digest := NewDigest(current, period, today)
	titles, err := s.titleMap(ctx, digest.TitleIDs())
	if err != nil {
		return PeriodStats{}, err
	}
	out := digest.Stats(titles)
	if previous != nil {
		prior := NewDigest(before, *previous, today).Totals()
		out.Prior = &prior
	}
	out.Music, err = s.music(ctx, userID, period, previous)
	if err != nil {
		return PeriodStats{}, err
	}
	return out, nil
}

// Profile is GAM-006b: the profile's all-time numbers.
func (s *Service) Profile(ctx context.Context, userID uuid.UUID) (ProfileStats, error) {
	rows, err := s.q.StatsProfileLibrary(ctx, userID)
	if err != nil {
		return ProfileStats{}, fmt.Errorf("profile library: %w", err)
	}
	profile := make([]ProfileRow, 0, len(rows))
	for _, r := range rows {
		t, status := core.MediaType(r.Type), core.LibraryStatus(r.Status)
		if !t.Valid() || !status.Valid() {
			continue
		}
		profile = append(profile, ProfileRow{
			TitleID: r.TitleID, Type: t, IsAnime: r.IsAnime, Status: status, Rating: r.Rating,
			Episodes: int(r.Episodes), Minutes: int(r.Minutes), Pages: int(r.Pages), Genres: r.Genres, Network: r.Network,
		})
	}
	var memberSince *time.Time
	joined, err := s.q.StatsMemberSince(ctx, userID)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		return ProfileStats{}, fmt.Errorf("member since: %w", err)
	default:
		memberSince = &joined
	}
	digest := NewProfileDigest(profile)
	titles, err := s.titleMap(ctx, digest.TitleIDs())
	if err != nil {
		return ProfileStats{}, err
	}
	return digest.Stats(titles, memberSince), nil
}

// Activity is the user's activity on local days in [from, until) of zone, ordered by day.
func (s *Service) Activity(ctx context.Context, userID uuid.UUID, from, until LocalDay, zone *time.Location) ([]Activity, error) {
	rows, err := s.q.StatsActivity(ctx, sqlc.StatsActivityParams{
		FromDay: from.String(), UntilDay: until.String(), Zone: zone.String(), UserID: userID,
	})
	if err != nil {
		return nil, fmt.Errorf("stats activity: %w", err)
	}
	out := make([]Activity, 0, len(rows))
	for _, r := range rows {
		day, ok := ParseDay(r.Day)
		t := core.MediaType(r.Type)
		if !ok || !t.Valid() {
			continue
		}
		out = append(out, Activity{
			Day: day, TitleID: r.TitleID, Type: t, IsAnime: r.IsAnime, Rating: r.Rating, Episodes: int(r.Episodes),
			Minutes: int(r.Minutes), Finished: r.Finished, FirstAt: r.FirstAt.Time, LastAt: r.LastAt.Time, Genres: r.Genres,
		})
	}
	return out, nil
}

func (s *Service) titleMap(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]core.Title, error) {
	titles, err := s.titles.Titles(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := make(map[uuid.UUID]core.Title, len(titles))
	for _, t := range titles {
		if _, ok := out[t.ID]; !ok {
			out[t.ID] = t
		}
	}
	return out, nil
}
