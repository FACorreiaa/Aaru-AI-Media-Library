// Package stats is GAM-006a…e and MUS-008: period stats for the Recap and Insights, and the
// profile's all-time numbers (GAM-006b). Derived reads over the user's own library with no table
// of their own; imported, restored and caught-up ticks are never activity.
package stats

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// LocalDay is a calendar day in the user's time zone, with no time of day.
type LocalDay struct {
	Year, Month, Day int
}

// ParseDay reads `YYYY-MM-DD`, as Postgres prints a `date`.
func ParseDay(text string) (LocalDay, bool) {
	parts := strings.Split(text, "-")
	if len(parts) != 3 {
		return LocalDay{}, false
	}
	var n [3]int
	for i, p := range parts {
		v, err := strconv.Atoi(p)
		if err != nil {
			return LocalDay{}, false
		}
		n[i] = v
	}
	return LocalDay{Year: n[0], Month: n[1], Day: n[2]}, true
}

// DayOf is the day the instant falls on in loc.
func DayOf(t time.Time, loc *time.Location) LocalDay {
	y, m, d := t.In(loc).Date()
	return LocalDay{Year: y, Month: int(m), Day: d}
}

func (d LocalDay) String() string {
	return fmt.Sprintf("%04d-%02d-%02d", d.Year, d.Month, d.Day)
}

// Adding is Gregorian arithmetic on bare dates (UTC, so no day is 23 or 25 hours long). Months
// go first and clamp to the month's last day, as Foundation's Calendar does.
func (d LocalDay) Adding(days, months int) LocalDay {
	y, m := d.Year, d.Month+months
	y += (m - 1) / 12
	m = (m-1)%12 + 1
	if m <= 0 {
		m += 12
		y--
	}
	day := d.Day
	if last := time.Date(y, time.Month(m)+1, 0, 0, 0, 0, 0, time.UTC).Day(); day > last {
		day = last
	}
	t := time.Date(y, time.Month(m), day, 0, 0, 0, 0, time.UTC).AddDate(0, 0, days)
	return DayOf(t, time.UTC)
}

// Less orders days.
func (d LocalDay) Less(o LocalDay) bool {
	if d.Year != o.Year {
		return d.Year < o.Year
	}
	if d.Month != o.Month {
		return d.Month < o.Month
	}
	return d.Day < o.Day
}

// Span is one calendar year, one month of it, all time, or the last 7 or 30 days.
type Span string

// The spans.
const (
	SpanMonth  Span = "month"
	SpanYear   Span = "year"
	SpanAll    Span = "all"
	SpanLast7  Span = "last7"
	SpanLast30 Span = "last30"
)

// Days is a rolling span's length (GAM-006d); 0 for calendar spans.
func (s Span) Days() int {
	switch s {
	case SpanLast7:
		return 7
	case SpanLast30:
		return 30
	default:
		return 0
	}
}

// FirstDay is the earliest day any period reaches (the years' lower bound).
var FirstDay = LocalDay{Year: 1900, Month: 1, Day: 1}

// Period is a span in one time zone.
type Period struct {
	Span Span
	// Year is the last year the period touches: the year asked for, or this year for all time.
	Year int
	// Month is nil unless the span is a month.
	Month    *int
	TimeZone *time.Location
	// Start is the first day; End the first day after.
	Start, End LocalDay
	// FirstYear is, for all time, the first year with activity, where the yearly buckets start.
	FirstYear int
}

// CalendarPeriod is a year, or one month of it.
func CalendarPeriod(year int, month *int, zone *time.Location) Period {
	p := Period{Span: SpanYear, Year: year, Month: month, TimeZone: zone, FirstYear: year}
	start := LocalDay{Year: year, Month: 1, Day: 1}
	months := 12
	if month != nil {
		p.Span = SpanMonth
		start.Month = *month
		months = 1
	}
	p.Start, p.End = start, start.Adding(0, months)
	return p
}

// AllTimeUntil is everything through the end of today's year, one bucket per year. It ends where
// the year's own period ends, so all time is exactly the years summed.
func AllTimeUntil(today LocalDay, zone *time.Location) Period {
	return Period{
		Span: SpanAll, Year: today.Year, TimeZone: zone, Start: FirstDay,
		End: LocalDay{Year: today.Year + 1, Month: 1, Day: 1}, FirstYear: today.Year,
	}
}

// LastDays is GAM-006d: the span's days ending with today, one bucket per day.
func LastDays(span Span, today LocalDay, zone *time.Location) Period {
	days := span.Days()
	if days == 0 {
		days = 7
	}
	return rolling(span, today.Adding(1-days, 0), today.Adding(1, 0), zone)
}

func rolling(span Span, from, until LocalDay, zone *time.Location) Period {
	year := until.Adding(-1, 0).Year
	return Period{Span: span, Year: year, TimeZone: zone, Start: from, End: until, FirstYear: year}
}

// Previous is a rolling span's equal-length window just before it; nil for calendar spans.
func (p Period) Previous() *Period {
	days := p.Span.Days()
	if days == 0 {
		return nil
	}
	prev := rolling(p.Span, p.Start.Adding(-days, 0), p.Start, p.TimeZone)
	return &prev
}

// LastDay is the period's last day, inclusive.
func (p Period) LastDay() LocalDay { return p.End.Adding(-1, 0) }

// BucketStarts are the months of the year, the days of the month or rolling span, or the years
// from FirstYear, in order.
func (p Period) BucketStarts() []LocalDay {
	var out []LocalDay
	switch p.Span {
	case SpanAll:
		for y := min(p.FirstYear, p.Year); y <= p.Year; y++ {
			out = append(out, LocalDay{Year: y, Month: 1, Day: 1})
		}
	case SpanYear:
		for m := range 12 {
			out = append(out, p.Start.Adding(0, m))
		}
	default:
		for d := p.Start; d.Less(p.End); d = d.Adding(1, 0) {
			out = append(out, d)
		}
	}
	return out
}

// Bucket is the bucket a day falls in.
func (p Period) Bucket(day LocalDay) LocalDay {
	switch p.Span {
	case SpanAll:
		return LocalDay{Year: day.Year, Month: 1, Day: 1}
	case SpanYear:
		return LocalDay{Year: day.Year, Month: day.Month, Day: 1}
	default:
		return day
	}
}
