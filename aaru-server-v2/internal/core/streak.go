package core

import (
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"
	"time"
)

// StreakDay is one local day with at least one live progress write (GAM-003). The
// server stores these as `check_ins`; the UI calls them streak days. Date is
// `yyyy-MM-dd` in TimeZone.
type StreakDay struct {
	Date     string    `json:"date"`
	TimeZone string    `json:"timeZone"`
	FirstAt  time.Time `json:"firstAt"`
}

// StreakRun is a run of consecutive streak days, first and last date inclusive.
type StreakRun struct {
	Start string
	End   string
	Days  int
}

// StreakSummary is the live and the longest run.
type StreakSummary struct {
	// Current is the days in the run that is still alive (its last day is today or
	// yesterday); 0 when broken.
	Current int
	Longest int
	// Today is whether today already counts.
	Today bool
	// RunStart is the live run's first date, the key for its milestone bonuses.
	RunStart *string
}

// StreakMilestones are the run lengths that earn a bonus.
var StreakMilestones = []int{7, 30, 100, 365}

// StreakTravelGrace bridges one missing date across time zones.
const StreakTravelGrace = 48 * time.Hour

type numberedDay struct {
	number int
	day    StreakDay
}

// StreakRuns is the streak rule, shared by the server and the widget so both agree
// at midnight.
//
// Days are never recomputed: a day belongs to the date it was written under, so
// changing time zone never breaks a streak after the fact. One allowance for
// travel: a single missing date is bridged when the days either side were written
// in different time zones and their first writes are at most 48 hours apart.
func StreakRuns(days []StreakDay) []StreakRun {
	var sorted []numberedDay
	for _, day := range days {
		if n, ok := DayNumber(day.Date); ok {
			sorted = append(sorted, numberedDay{number: n, day: day})
		}
	}
	slices.SortStableFunc(sorted, func(a, b numberedDay) int { return a.number - b.number })
	var runs []StreakRun
	var previous *numberedDay
	for i := range sorted {
		entry := sorted[i]
		switch {
		case previous != nil && len(runs) > 0 && continues(*previous, entry):
			run := &runs[len(runs)-1]
			run.End = entry.day.Date
			run.Days++
		case previous == nil || previous.number != entry.number:
			runs = append(runs, StreakRun{Start: entry.day.Date, End: entry.day.Date, Days: 1})
		}
		previous = &sorted[i]
	}
	return runs
}

// SummarizeStreak is the live run as of today (`yyyy-MM-dd`).
func SummarizeStreak(days []StreakDay, today string) StreakSummary {
	all := StreakRuns(days)
	longest := 0
	for _, run := range all {
		longest = max(longest, run.Days)
	}
	if len(all) == 0 {
		return StreakSummary{Longest: longest}
	}
	last := all[len(all)-1]
	end, ok1 := DayNumber(last.End)
	now, ok2 := DayNumber(today)
	if !ok1 || !ok2 {
		return StreakSummary{Longest: longest}
	}
	alive := now-end <= 1 && now >= end
	summary := StreakSummary{Longest: longest, Today: end == now}
	if alive {
		start := last.Start
		summary.Current, summary.RunStart = last.Days, &start
	}
	return summary
}

// LocalDate is `yyyy-MM-dd` for instant in loc.
func LocalDate(instant time.Time, loc *time.Location) string {
	y, m, d := instant.In(loc).Date()
	return fmt.Sprintf("%04d-%02d-%02d", y, int(m), d)
}

// AddingDays is the date days after date (negative goes back).
func AddingDays(days int, date string) (string, bool) {
	n, ok := DayNumber(date)
	if !ok {
		return "", false
	}
	return dateString(n + days), true
}

// DayNumber is days since 1970-01-01 for a `yyyy-MM-dd` string.
func DayNumber(date string) (int, bool) {
	var parts []int
	for p := range strings.SplitSeq(date, "-") {
		if p == "" {
			continue
		}
		if n, err := strconv.Atoi(p); err == nil {
			parts = append(parts, n)
		}
	}
	if len(parts) != 3 {
		return 0, false
	}
	instant := time.Date(parts[0], time.Month(parts[1]), parts[2], 0, 0, 0, 0, time.UTC)
	return int(math.Floor(float64(instant.Unix()) / 86400)), true
}

func dateString(dayNumber int) string {
	return LocalDate(time.Unix(int64(dayNumber)*86400, 0), time.UTC)
}

func continues(last, next numberedDay) bool {
	switch next.number - last.number {
	case 1:
		return true
	case 2:
		return last.day.TimeZone != next.day.TimeZone && next.day.FirstAt.Sub(last.day.FirstAt) <= StreakTravelGrace
	}
	return false
}
