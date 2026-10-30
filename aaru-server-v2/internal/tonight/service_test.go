package tonight

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/schedule"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ported from TonightRankingTests (TonightTests.swift).

const day = 24 * time.Hour

var (
	now     = time.Unix(1_792_000_000, 0).UTC()
	lisbon  = mustZone("Europe/Lisbon")
	today   = localDay(now, lisbon)
	episode = core.EpisodeKey{Season: 2, Episode: 4}
)

func mustZone(name string) *time.Location {
	z, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return z
}

func ptr[T any](v T) *T { return &v }

func show(name string, remaining int, finale bool) schedule.ContinueEntry {
	return schedule.ContinueEntry{
		LibraryItemID: uuid.New(), Title: core.Title{ID: uuid.New(), Type: core.MediaShow, Title: name},
		Next: episode, NextName: ptr("Woe's Hollow"), NextRuntimeMinutes: ptr(52),
		RemainingCount: remaining, RemainingMinutes: remaining * 52, IsFinale: finale,
	}
}

func film(name string) schedule.StartEntry {
	return schedule.StartEntry{LibraryItemID: uuid.New(), Title: core.Title{Type: core.MediaMovie, Title: name}, RuntimeMinutes: ptr(124)}
}

func book(name string, pages, page *int, changed time.Duration) ReadingEntry {
	return ReadingEntry{
		LibraryItemID: uuid.New(), Title: core.Title{Type: core.MediaBook, Title: name, PageCount: pages},
		PageCount: pages, BookPage: page, LastChange: now.Add(-changed),
	}
}

func rank(l Library, feedback ...Feedback) []Pick { return Rank(l, feedback, today, now, lisbon) }

func titles(picks []Pick) []string {
	out := []string{}
	for _, p := range picks {
		out = append(out, p.Title.Title)
	}
	return out
}

func TestMomentumAndNearnessOrderShows(t *testing.T) {
	stale, fresh := show("Stale", 8, false), show("Fresh", 8, false)
	// Scores: Fresh 5, Ending 4.5, Stale and Extra 3 (a tie the id breaks).
	ending, extra := show("Ending", 3, false), show("Extra", 8, false)
	l := Library{Continuing: []schedule.ContinueEntry{stale, fresh, ending, extra}, Dates: map[uuid.UUID]ItemDates{
		stale.LibraryItemID:  {AddedAt: now, LastChange: now.Add(-30 * day)},
		fresh.LibraryItemID:  {AddedAt: now, LastChange: now.Add(-1 * day)},
		ending.LibraryItemID: {AddedAt: now, LastChange: now.Add(-20 * day)},
		extra.LibraryItemID:  {AddedAt: now, LastChange: now.Add(-40 * day)},
	}}
	picks := rank(l)
	require.Len(t, picks, 3)
	assert.Equal(t, []string{"Fresh", "Ending"}, titles(picks)[:2])
	assert.NotEqual(t, picks[2].LibraryItemID, picks[0].LibraryItemID)
	assert.Equal(t, "52 min · 3 left", picks[1].Reason)
	assert.Equal(t, &episode, picks[1].Episode)

	finale := rank(Library{Continuing: []schedule.ContinueEntry{show("Finale", 1, true)}})
	assert.Equal(t, "52 min · Last one aired · Season finale", finale[0].Reason)
}

func TestFeedbackHidesForTheDayAndWeighs(t *testing.T) {
	first, second := show("First", 8, false), show("Second", 8, false)
	l := Library{Continuing: []schedule.ContinueEntry{first, second}, Dates: map[uuid.UUID]ItemDates{
		first.LibraryItemID: {AddedAt: now, LastChange: now},
		// Scores 5 and 4: one rejection (-2) puts First below Second, with no tie.
		second.LibraryItemID: {AddedAt: now, LastChange: now.Add(-5 * day)},
	}}
	assert.Equal(t, "First", rank(l)[0].Title.Title)
	assert.Equal(t, []string{"Second"}, titles(rank(l, Feedback{LibraryItemID: first.LibraryItemID, Verdict: VerdictNotTonight, Day: today, CreatedAt: now})))
	yesterday, _ := core.AddingDays(-1, today)
	assert.Equal(t, "First", rank(l, Feedback{LibraryItemID: first.LibraryItemID, Verdict: VerdictNotTonight, Day: yesterday, CreatedAt: now})[0].Title.Title)
	assert.Equal(t, []string{"Second", "First"}, titles(rank(l, Feedback{LibraryItemID: first.LibraryItemID, Verdict: VerdictRejected, Day: today, CreatedAt: now})))
}

func TestBooksAndFilms(t *testing.T) {
	near := book("Dune", ptr(600), ptr(536), 10*day)
	unknown := book("Untracked", nil, nil, 10*day)
	perfectDays := film("Perfect Days")
	wishlistShow := schedule.StartEntry{LibraryItemID: uuid.New(), Title: core.Title{Type: core.MediaShow, Title: "Not a film"}, RuntimeMinutes: ptr(50)}
	l := Library{
		Starting: []schedule.StartEntry{perfectDays, wishlistShow}, Reading: []ReadingEntry{near, unknown},
		Dates: map[uuid.UUID]ItemDates{perfectDays.LibraryItemID: {AddedAt: now.Add(-41 * day), LastChange: now}},
	}
	picks := rank(l)
	assert.Equal(t, []string{"Dune", "Perfect Days", "Untracked"}, titles(picks))
	assert.Equal(t, "64 pages left", picks[0].Reason)
	assert.Equal(t, KindReading, picks[0].Kind)
	assert.Equal(t, "2 h 04 · On your list 41 days", picks[1].Reason)
	assert.Equal(t, ptr(124), picks[1].Minutes)
	assert.Equal(t, "Reading", picks[2].Reason)

	percent := book("Half", nil, nil, 0)
	percent.BookPercent = ptr(42.5)
	assert.Equal(t, "43% read", rank(Library{Reading: []ReadingEntry{percent}})[0].Reason)
	one := book("Last page", ptr(100), ptr(99), 0)
	assert.Equal(t, "1 page left", rank(Library{Reading: []ReadingEntry{one}})[0].Reason)
}

func TestAiringShowsLocalTime(t *testing.T) {
	behind := show("Behind", 8, false)
	airsAt := time.Date(2026, 10, 22, 20, 0, 0, 0, time.UTC)
	airing := func(item uuid.UUID, name string) schedule.CalendarEntry {
		return schedule.CalendarEntry{
			LibraryItemID: item, Title: core.Title{Type: core.MediaShow, Title: name}, Key: core.EpisodeKey{Season: 1, Episode: 1},
			AirsAt: airsAt, RuntimeMinutes: ptr(44), Kind: schedule.KindPremiere, AirTimeKnown: true,
		}
	}
	picks := rank(Library{
		Continuing: []schedule.ContinueEntry{behind},
		Airing:     []schedule.CalendarEntry{airing(uuid.New(), "New"), airing(behind.LibraryItemID, "Behind")},
	})
	assert.Equal(t, []string{"New", "Behind"}, titles(picks))
	assert.Equal(t, "Airs 21:00 · 44 min · Premiere", picks[0].Reason)
	assert.Equal(t, KindContinue, picks[1].Kind)
}

func TestDurations(t *testing.T) {
	assert.Equal(t, "52 min", Duration(52))
	assert.Equal(t, "1 h 00", Duration(60))
	assert.Equal(t, "2 h 04", Duration(124))
}

func TestZoneAndBounds(t *testing.T) {
	_, err := Zone(ptr("Mars/Olympus"))
	require.Error(t, err)
	_, err = Zone(ptr("Local"))
	require.Error(t, err)
	z, err := Zone(nil)
	require.NoError(t, err)
	assert.Equal(t, time.UTC, z)
	start, end := Bounds(time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC), lisbon)
	// The day Lisbon leaves summer time is 25 hours long.
	assert.Equal(t, time.Date(2026, 10, 24, 23, 0, 0, 0, time.UTC), start.UTC())
	assert.Equal(t, 25*time.Hour, end.Sub(start))
}
