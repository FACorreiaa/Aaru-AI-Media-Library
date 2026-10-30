// Package tonight is Tonight (AG-005): one to three things to start tonight, from the user's own
// library only. The ranking is a fixed score, so the same library gives the same strip; reasons are
// templates, so no model is ever called and Home works with the agent off.
package tonight

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/schedule"
	"aaru-go-api/internal/telemetry"
	"context"
	"fmt"
	"math"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/sync/errgroup"
)

const (
	// MaxPicks is the strip's length.
	MaxPicks = 3
	// RejectionWindow is how long "not for me" weighs against an item.
	RejectionWindow = 14 * 24 * time.Hour
	// RejectionPenalty is subtracted per "not for me" in the window.
	RejectionPenalty = 2.0
)

// Kind is why a pick is on the strip.
type Kind string

// The pick kinds.
const (
	// KindContinue is the next aired episode of a show in progress.
	KindContinue Kind = "continue"
	// KindAiring is an episode of a tracked show airing today.
	KindAiring Kind = "airing"
	// KindReading is a book in progress.
	KindReading Kind = "reading"
	// KindStart is a film on the wishlist.
	KindStart Kind = "start"
)

// Pick is one thing to start tonight, with why it is here and about how long it takes.
type Pick struct {
	LibraryItemID uuid.UUID
	Title         core.Title
	Kind          Kind
	Episode       *core.EpisodeKey
	EpisodeName   *string
	Minutes       *int
	AirsAt        *time.Time
	AirTimeKnown  bool
	// Reason is "52 min · 3 left", "Airs 21:00 · 44 min", "64 pages left", "2 h 04 · On your list 41 days".
	Reason string
}

// Tonight is the strip for one local day (YYYY-MM-DD).
type Tonight struct {
	Day   string
	Picks []Pick
}

// Verdict is the user's answer to a pick. "Not tonight" hides it for the day; "not for me"
// (rejected) weighs against it for two weeks.
type Verdict string

// The verdicts.
const (
	VerdictRejected   Verdict = "rejected"
	VerdictNotTonight Verdict = "not_tonight"
)

// Feedback is one verdict.
type Feedback struct {
	LibraryItemID uuid.UUID
	Verdict       Verdict
	Day           string
	CreatedAt     time.Time
}

// ReadingEntry is a book in progress.
type ReadingEntry struct {
	LibraryItemID uuid.UUID
	Title         core.Title
	PageCount     *int
	BookPage      *int
	BookPercent   *float64
	LastChange    time.Time
}

// ItemDates is when the user last touched an item, and when it joined the library.
type ItemDates struct {
	AddedAt, LastChange time.Time
}

// Library is what Tonight ranks: the rows Home already reads, plus books in progress.
type Library struct {
	Continuing []schedule.ContinueEntry
	Airing     []schedule.CalendarEntry
	Starting   []schedule.StartEntry
	Reading    []ReadingEntry
	Dates      map[uuid.UUID]ItemDates
}

func (l Library) itemIDs() []uuid.UUID {
	ids := make([]uuid.UUID, 0, len(l.Continuing)+len(l.Starting))
	for _, c := range l.Continuing {
		ids = append(ids, c.LibraryItemID)
	}
	for _, s := range l.Starting {
		ids = append(ids, s.LibraryItemID)
	}
	return ids
}

// Service is TonightService.
type Service struct {
	q        *sqlc.Queries
	schedule *schedule.Service
	// Now is the clock; tests pin it.
	Now func() time.Time
}

// New builds the service.
func New(q *sqlc.Queries, schedule *schedule.Service) *Service {
	return &Service{q: q, schedule: schedule, Now: time.Now}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Tonight is the strip for the local day now falls on in the zone (nil: UTC).
func (s *Service) Tonight(ctx context.Context, userID uuid.UUID, zoneName *string) (Tonight, error) {
	zone, err := Zone(zoneName)
	if err != nil {
		return Tonight{}, err
	}
	now := s.now()
	day := localDay(now, zone)
	start, end := Bounds(now, zone)
	var (
		library  Library
		feedback []Feedback
	)
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() (err error) {
		library.Continuing, err = s.schedule.ContinueWatching(gctx, userID, now, 50)
		return err
	})
	g.Go(func() (err error) {
		library.Airing, err = s.schedule.CalendarBetween(gctx, userID, start, end)
		return err
	})
	g.Go(func() (err error) {
		library.Starting, err = s.schedule.StartWatching(gctx, userID, 50)
		return err
	})
	g.Go(func() (err error) {
		library.Reading, err = s.reading(gctx, userID, 20)
		return err
	})
	g.Go(func() (err error) {
		feedback, err = s.feedbackSince(gctx, userID, now.Add(-RejectionWindow))
		return err
	})
	if err := g.Wait(); err != nil {
		return Tonight{}, err
	}
	if library.Dates, err = s.itemDates(ctx, library.itemIDs(), userID); err != nil {
		return Tonight{}, err
	}
	picks := Rank(library, feedback, day, now, zone)
	first, err := s.recordPicks(ctx, picks, day, userID, now)
	if err != nil {
		return Tonight{}, err
	}
	if first {
		telemetry.Capture(telemetry.TonightShown, userID, nil)
	}
	return Tonight{Day: day, Picks: picks}, nil
}

// SaveFeedback records a verdict on today's strip; 404 when the item is not the user's.
func (s *Service) SaveFeedback(ctx context.Context, userID, itemID uuid.UUID, verdict Verdict, zoneName *string) error {
	zone, err := Zone(zoneName)
	if err != nil {
		return err
	}
	now := s.now()
	saved, err := s.q.TonightSaveFeedback(ctx, sqlc.TonightSaveFeedbackParams{
		ID: uuid.New(), Verdict: string(verdict), Day: localDay(now, zone),
		CreatedAt: pgtype.Timestamptz{Time: now, Valid: true}, LibraryItemID: itemID, UserID: userID,
	})
	if err != nil {
		return fmt.Errorf("save tonight feedback: %w", err)
	}
	if len(saved) == 0 {
		return apperr.NotFound("No such library item.")
	}
	telemetry.Capture(telemetry.TonightRejected, userID, map[string]string{"verdict": string(verdict)})
	return nil
}

// ClearFeedback is the Undo after "Not tonight" or "Not for me": today's verdict on the item, gone.
// Nothing to take back, or an item that is not the user's, changes nothing.
func (s *Service) ClearFeedback(ctx context.Context, userID, itemID uuid.UUID, zoneName *string) error {
	zone, err := Zone(zoneName)
	if err != nil {
		return err
	}
	err = s.q.TonightClearFeedback(ctx, sqlc.TonightClearFeedbackParams{
		UserID: userID, LibraryItemID: itemID, Day: localDay(s.now(), zone),
	})
	if err != nil {
		return fmt.Errorf("clear tonight feedback: %w", err)
	}
	return nil
}

// MARK: Ranking

type scored struct {
	pick  Pick
	score float64
}

// Rank scores the library, highest first:
//   - a show in progress: 3, plus momentum, plus 1.5 when three or fewer episodes are left and
//     0.5 when the next one ends its season;
//   - an episode airing today of a show not already in Continue watching: 3.5;
//   - a book in progress: 2.5, plus momentum, plus 1.5 when 80% read or 50 pages or fewer left;
//   - a wishlist film: 1.5, plus up to 1.5 for time on the list (one point a month);
//   - minus 2 for each "not for me" in the last 14 days. "Not tonight" hides an item until the
//     local day ends.
//
// Momentum is 2 when the item changed in the last two days, 1 in the last week.
func Rank(library Library, feedback []Feedback, day string, now time.Time, zone *time.Location) []Pick {
	hidden := map[uuid.UUID]bool{}
	rejections := map[uuid.UUID]int{}
	for _, f := range feedback {
		switch {
		case f.Verdict == VerdictNotTonight && f.Day == day:
			hidden[f.LibraryItemID] = true
		case f.Verdict == VerdictRejected:
			rejections[f.LibraryItemID]++
		}
	}
	momentum := func(lastChange *time.Time) float64 {
		if lastChange == nil {
			return 0
		}
		days := now.Sub(*lastChange).Hours() / 24
		switch {
		case days <= 2:
			return 2
		case days <= 7:
			return 1
		}
		return 0
	}

	var all []scored
	continuing := map[uuid.UUID]bool{}
	for _, entry := range library.Continuing {
		continuing[entry.LibraryItemID] = true
		var last *time.Time
		if d, ok := library.Dates[entry.LibraryItemID]; ok {
			last = &d.LastChange
		}
		score := 3 + momentum(last)
		if entry.RemainingCount <= 3 {
			score += 1.5
		}
		if entry.IsFinale {
			score += 0.5
		}
		all = append(all, scored{continuePick(entry), score})
	}
	// An airing of a show the user is behind on waits: its Continue watching pick comes first.
	for _, entry := range library.Airing {
		if !entry.Watched && !continuing[entry.LibraryItemID] {
			all = append(all, scored{airingPick(entry, zone), 3.5})
		}
	}
	for _, entry := range library.Reading {
		var left *int
		var fraction *float64
		if entry.PageCount != nil && entry.BookPage != nil {
			l := max(*entry.PageCount-*entry.BookPage, 0)
			left = &l
		}
		switch {
		case entry.BookPercent != nil:
			f := *entry.BookPercent / 100
			fraction = &f
		case entry.PageCount != nil && entry.BookPage != nil:
			f := float64(*entry.BookPage) / float64(max(*entry.PageCount, 1))
			fraction = &f
		}
		near := (fraction != nil && *fraction >= 0.8) || (left != nil && *left <= 50)
		score := 2.5 + momentum(&entry.LastChange)
		if near {
			score += 1.5
		}
		all = append(all, scored{readingPick(entry, left), score})
	}
	for _, entry := range library.Starting {
		if entry.Title.Type != core.MediaMovie {
			continue
		}
		var days *int
		if d, ok := library.Dates[entry.LibraryItemID]; ok {
			n := max(int(now.Sub(d.AddedAt).Hours()/24), 0)
			days = &n
		}
		listed := 0.0
		if days != nil {
			listed = float64(*days)
		}
		all = append(all, scored{startPick(entry, days), 1.5 + math.Min(listed/30, 1.5)})
	}

	ranked := make([]scored, 0, len(all))
	for _, sc := range all {
		if hidden[sc.pick.LibraryItemID] {
			continue
		}
		sc.score -= float64(rejections[sc.pick.LibraryItemID]) * RejectionPenalty
		ranked = append(ranked, sc)
	}
	// Ties go to the smaller id as Swift's uuidString orders it (upper-case; the order is the same).
	slices.SortStableFunc(ranked, func(a, b scored) int {
		if a.score != b.score {
			if a.score > b.score {
				return -1
			}
			return 1
		}
		return strings.Compare(strings.ToUpper(a.pick.LibraryItemID.String()), strings.ToUpper(b.pick.LibraryItemID.String()))
	})
	seen := map[uuid.UUID]bool{}
	picks := []Pick{}
	for _, sc := range ranked {
		if len(picks) >= MaxPicks {
			break
		}
		if seen[sc.pick.LibraryItemID] {
			continue
		}
		seen[sc.pick.LibraryItemID] = true
		picks = append(picks, sc.pick)
	}
	return picks
}

// MARK: Reasons

func continuePick(e schedule.ContinueEntry) Pick {
	parts := []string{}
	if e.NextRuntimeMinutes != nil {
		parts = append(parts, Duration(*e.NextRuntimeMinutes))
	}
	if e.RemainingCount > 1 {
		parts = append(parts, strconv.Itoa(e.RemainingCount)+" left")
	} else {
		parts = append(parts, "Last one aired")
	}
	if e.IsFinale {
		parts = append(parts, "Season finale")
	}
	next := e.Next
	return Pick{
		LibraryItemID: e.LibraryItemID, Title: e.Title, Kind: KindContinue, Episode: &next,
		EpisodeName: e.NextName, Minutes: e.NextRuntimeMinutes, Reason: joined(parts),
	}
}

func airingPick(e schedule.CalendarEntry, zone *time.Location) Pick {
	parts := []string{"Airs today"}
	if e.AirTimeKnown {
		parts[0] = "Airs " + e.AirsAt.In(zone).Format("15:04")
	}
	if e.RuntimeMinutes != nil {
		parts = append(parts, Duration(*e.RuntimeMinutes))
	}
	switch e.Kind {
	case schedule.KindPremiere:
		parts = append(parts, "Premiere")
	case schedule.KindFinale:
		parts = append(parts, "Finale")
	case schedule.KindRegular:
	}
	key, airsAt := e.Key, e.AirsAt
	return Pick{
		LibraryItemID: e.LibraryItemID, Title: e.Title, Kind: KindAiring, Episode: &key,
		EpisodeName: e.EpisodeName, Minutes: e.RuntimeMinutes, AirsAt: &airsAt, AirTimeKnown: e.AirTimeKnown,
		Reason: joined(parts),
	}
}

func readingPick(e ReadingEntry, pagesLeft *int) Pick {
	var reason string
	switch {
	case pagesLeft != nil && *pagesLeft == 1:
		reason = "1 page left"
	case pagesLeft != nil:
		reason = strconv.Itoa(*pagesLeft) + " pages left"
	case e.BookPercent != nil:
		reason = strconv.Itoa(int(math.Round(*e.BookPercent))) + "% read"
	default:
		reason = "Reading"
	}
	return Pick{LibraryItemID: e.LibraryItemID, Title: e.Title, Kind: KindReading, Reason: reason}
}

func startPick(e schedule.StartEntry, daysOnList *int) Pick {
	parts := []string{}
	if e.RuntimeMinutes != nil {
		parts = append(parts, Duration(*e.RuntimeMinutes))
	}
	if daysOnList != nil {
		switch *daysOnList {
		case 0:
			parts = append(parts, "Added today")
		case 1:
			parts = append(parts, "On your list 1 day")
		default:
			parts = append(parts, "On your list "+strconv.Itoa(*daysOnList)+" days")
		}
	}
	return Pick{
		LibraryItemID: e.LibraryItemID, Title: e.Title, Kind: KindStart, Minutes: e.RuntimeMinutes, Reason: joined(parts),
	}
}

// Duration is "52 min" or "2 h 04".
func Duration(minutes int) string {
	if minutes < 60 {
		return strconv.Itoa(minutes) + " min"
	}
	return fmt.Sprintf("%d h %02d", minutes/60, minutes%60)
}

func joined(parts []string) string { return strings.Join(parts, " · ") }

// MARK: Days

// Bounds is the local day now falls on, as a UTC range.
func Bounds(now time.Time, zone *time.Location) (time.Time, time.Time) {
	local := now.In(zone)
	start := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone)
	return start, start.AddDate(0, 0, 1)
}

func localDay(t time.Time, zone *time.Location) string { return t.In(zone).Format(time.DateOnly) }

// Zone is the IANA zone the client named; absent is UTC.
func Zone(name *string) (*time.Location, error) {
	if name == nil {
		return time.UTC, nil
	}
	const message = "Use an IANA time zone such as Europe/Lisbon."
	zone, err := time.LoadLocation(*name)
	if err != nil || *name == "" || *name == "Local" {
		return nil, apperr.New(http.StatusUnprocessableEntity, "validation_failed", message).
			WithDetails(map[string]string{"tz": message})
	}
	return zone, nil
}

// MARK: Store

func (s *Service) reading(ctx context.Context, userID uuid.UUID, limit int32) ([]ReadingEntry, error) {
	rows, err := s.q.TonightReading(ctx, sqlc.TonightReadingParams{UserID: userID, MaxRows: limit})
	if err != nil {
		return nil, fmt.Errorf("tonight reading: %w", err)
	}
	out := make([]ReadingEntry, 0, len(rows))
	for _, row := range rows {
		title, ok := schedule.TitleFromRow(row.Title)
		if !ok {
			continue
		}
		out = append(out, ReadingEntry{
			LibraryItemID: row.ItemID, Title: title, PageCount: intPtr(row.Title.PageCount),
			BookPage: intPtr(row.BookPage), BookPercent: row.BookPercent, LastChange: row.UpdatedAt,
		})
	}
	return out, nil
}

func (s *Service) itemDates(ctx context.Context, ids []uuid.UUID, userID uuid.UUID) (map[uuid.UUID]ItemDates, error) {
	out := map[uuid.UUID]ItemDates{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := s.q.TonightItemDates(ctx, sqlc.TonightItemDatesParams{UserID: userID, Ids: ids})
	if err != nil {
		return nil, fmt.Errorf("tonight item dates: %w", err)
	}
	for _, row := range rows {
		out[row.ID] = ItemDates{AddedAt: row.AddedAt, LastChange: row.UpdatedAt}
	}
	return out, nil
}

func (s *Service) feedbackSince(ctx context.Context, userID uuid.UUID, since time.Time) ([]Feedback, error) {
	rows, err := s.q.TonightFeedbackSince(ctx, sqlc.TonightFeedbackSinceParams{UserID: userID, Since: since})
	if err != nil {
		return nil, fmt.Errorf("tonight feedback: %w", err)
	}
	out := make([]Feedback, 0, len(rows))
	for _, row := range rows {
		v := Verdict(row.Verdict)
		if v != VerdictRejected && v != VerdictNotTonight {
			continue
		}
		out = append(out, Feedback{LibraryItemID: row.LibraryItemID, Verdict: v, Day: row.Day, CreatedAt: row.CreatedAt})
	}
	return out, nil
}

// recordPicks records what the strip showed on day, the latest showing winning. True when this is
// the first time the strip showed anything that day.
func (s *Service) recordPicks(ctx context.Context, picks []Pick, day string, userID uuid.UUID, servedAt time.Time) (bool, error) {
	if len(picks) == 0 {
		return false, nil
	}
	shown, err := s.q.TonightShownOn(ctx, sqlc.TonightShownOnParams{UserID: userID, Day: day})
	if err != nil {
		return false, fmt.Errorf("tonight shown: %w", err)
	}
	for rank, p := range picks {
		err := s.q.TonightRecordPick(ctx, sqlc.TonightRecordPickParams{
			UserID: userID, Day: day, LibraryItemID: p.LibraryItemID, Rank: int16(rank), ServedAt: servedAt, //nolint:gosec // at most MaxPicks
		})
		if err != nil {
			return false, fmt.Errorf("tonight pick: %w", err)
		}
	}
	return !shown, nil
}

func intPtr(v *int32) *int {
	if v == nil {
		return nil
	}
	n := int(*v)
	return &n
}

// AcceptPicks is the library's hook after a progress write (episode, season or show ticks, field
// edits) on these items: picks shown in the last six hours become taken, and tonight_accepted is
// counted once per local day. Counting never fails the write it follows, so the caller drops errors.
func AcceptPicks(ctx context.Context, q *sqlc.Queries, userID uuid.UUID, ids []uuid.UUID) error {
	if len(ids) == 0 {
		return nil
	}
	days, err := q.TonightAcceptPicks(ctx, sqlc.TonightAcceptPicksParams{UserID: userID, Ids: ids})
	if err != nil {
		return fmt.Errorf("accept tonight picks: %w", err)
	}
	for range days {
		telemetry.Capture(telemetry.TonightAccepted, userID, nil)
	}
	return nil
}
