package core

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func streakDay(t *testing.T, date, zone string, hoursAfterMidnightUTC float64) StreakDay {
	t.Helper()
	n, ok := DayNumber(date)
	require.True(t, ok)
	base := time.Unix(int64(n)*86400, 0).UTC()
	return StreakDay{Date: date, TimeZone: zone, FirstAt: base.Add(time.Duration(hoursAfterMidnightUTC * float64(time.Hour)))}
}

func lisbon(t *testing.T, dates ...string) []StreakDay {
	days := make([]StreakDay, 0, len(dates))
	for _, d := range dates {
		days = append(days, streakDay(t, d, "Europe/Lisbon", 12))
	}
	return days
}

func TestStreakLocalMidnightSplitsTwoDays(t *testing.T) {
	zone, err := time.LoadLocation("Europe/Lisbon")
	require.NoError(t, err)
	before := time.Date(2026, 10, 22, 22, 50, 0, 0, time.UTC)
	after := time.Date(2026, 10, 22, 23, 10, 0, 0, time.UTC)
	assert.Equal(t, "2026-10-22", LocalDate(before, zone))
	assert.Equal(t, "2026-10-23", LocalDate(after, zone))
	start := "2026-10-22"
	assert.Equal(t, StreakSummary{Current: 2, Longest: 2, Today: true, RunStart: &start},
		SummarizeStreak(lisbon(t, "2026-10-22", "2026-10-23"), "2026-10-23"))
}

func TestStreakAliveUntilTheEndOfTheNextDay(t *testing.T) {
	days := lisbon(t, "2026-10-20", "2026-10-21", "2026-10-22")
	assert.Equal(t, 3, SummarizeStreak(days, "2026-10-23").Current)
	assert.False(t, SummarizeStreak(days, "2026-10-23").Today)
	assert.Equal(t, 0, SummarizeStreak(days, "2026-10-24").Current)
	assert.Equal(t, 3, SummarizeStreak(days, "2026-10-24").Longest)
}

func TestStreakChangingTimeZoneNeverBreaksPastDays(t *testing.T) {
	days := []StreakDay{
		streakDay(t, "2026-10-20", "Europe/Lisbon", 12),
		streakDay(t, "2026-10-21", "America/New_York", 12),
		streakDay(t, "2026-10-22", "Asia/Tokyo", 12),
	}
	assert.Equal(t, 3, SummarizeStreak(days, "2026-10-22").Current)
}

func TestStreakTravelGraceBridgesOneSkippedDate(t *testing.T) {
	skipped := []StreakDay{
		streakDay(t, "2026-10-20", "America/Los_Angeles", 30),
		streakDay(t, "2026-10-22", "Asia/Tokyo", 2),
	}
	assert.Equal(t, 2, SummarizeStreak(skipped, "2026-10-22").Current)
	assert.Equal(t, 1, SummarizeStreak(lisbon(t, "2026-10-20", "2026-10-22"), "2026-10-22").Current)
	far := []StreakDay{
		streakDay(t, "2026-10-20", "Europe/Lisbon", 1),
		streakDay(t, "2026-10-22", "Asia/Tokyo", 23),
	}
	assert.Equal(t, 1, SummarizeStreak(far, "2026-10-22").Current)
}

func TestStreakRunsAndLongest(t *testing.T) {
	days := lisbon(t, "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-05", "2026-01-06")
	assert.Equal(t, []StreakRun{
		{Start: "2026-01-01", End: "2026-01-03", Days: 3},
		{Start: "2026-01-05", End: "2026-01-06", Days: 2},
	}, StreakRuns(days))
	assert.Equal(t, 3, SummarizeStreak(days, "2026-01-06").Longest)
	assert.Equal(t, StreakSummary{}, SummarizeStreak(nil, "2026-01-06"))
}

func TestStreakDateArithmetic(t *testing.T) {
	next, _ := AddingDays(1, "2026-12-31")
	assert.Equal(t, "2027-01-01", next)
	prev, _ := AddingDays(-1, "2026-03-01")
	assert.Equal(t, "2026-02-28", prev)
	n, _ := DayNumber("1970-01-02")
	assert.Equal(t, 1, n)
}

func TestShareLinks(t *testing.T) {
	for _, link := range []string{
		"https://aaruapp.com/s/k7Q2xPa9Lm3Z",
		"https://www.aaruapp.com/s/k7Q2xPa9Lm3Z",
		"https://beta.aaruapp.com/s/k7Q2xPa9Lm3Z/",
		"https://aaruapp.com/s/k7Q2xPa9Lm3Z?add=1",
	} {
		assert.Equal(t, "k7Q2xPa9Lm3Z", ShareLinkCode(link), link)
	}
	long := "https://aaruapp.com/s/"
	for range 33 {
		long += "a"
	}
	for _, link := range []string{
		"http://aaruapp.com/s/abc", "https://evil.example/s/abc", "https://aaruapp.com/s/",
		"https://aaruapp.com/s/a/b", "https://aaruapp.com/i/abc", "https://aaruapp.com/s/ab-c", long,
		"https://aaruapp.com/s/../x",
	} {
		assert.Empty(t, ShareLinkCode(link), link)
	}

	assert.True(t, ShareAutoAdd(true, true, true, false, false))
	assert.False(t, ShareAutoAdd(false, true, true, false, false), "not asked")
	assert.False(t, ShareAutoAdd(true, false, true, false, false), "signed out")
	assert.False(t, ShareAutoAdd(true, true, false, false, false), "not a title")
	assert.False(t, ShareAutoAdd(true, true, true, true, false), "unavailable")
	assert.False(t, ShareAutoAdd(true, true, true, false, true), "already theirs")

	status := func(s int) *int { return &s }
	assert.Equal(t, ShareMissing, ShareLoadFailureAfter(status(404), false))
	for _, s := range []*int{nil, status(429), status(500), status(503)} {
		assert.Equal(t, ShareRetry, ShareLoadFailureAfter(s, false))
	}
	for _, s := range []*int{nil, status(404), status(429), status(500)} {
		assert.Equal(t, ShareKeep, ShareLoadFailureAfter(s, true))
	}
}
