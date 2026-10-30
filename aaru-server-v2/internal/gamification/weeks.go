package gamification

import (
	"aaru-go-api/internal/core"
	"fmt"
	"strconv"
	"strings"
)

// ISOWeek is an ISO week (Monday to Sunday) by name and local dates.
type ISOWeek struct {
	Name  string
	From  string
	Until string
}

func mondayWeekday(day int) int {
	// 1970-01-01 was a Thursday: Monday-based weekday 3.
	return ((day % 7) + 7 + 3) % 7
}

func addOr(days int, date, fallback string) string {
	if out, ok := core.AddingDays(days, date); ok {
		return out
	}
	return fallback
}

// WeekContaining is the ISO week holding a local date.
func WeekContaining(date string) ISOWeek {
	day, _ := core.DayNumber(date)
	monday := day - mondayWeekday(day)
	from := addOr(monday-day, date, date)
	until := addOr(6, from, date)
	thursday := addOr(3, from, date)
	year := 1970
	if len(thursday) >= 4 {
		if y, err := strconv.Atoi(thursday[:4]); err == nil {
			year = y
		}
	}
	firstThursday := 0
	for offset := 1; offset <= 7; offset++ {
		number, ok := core.DayNumber(fmt.Sprintf("%04d-01-%02d", year, offset))
		if ok && mondayWeekday(number) == 3 {
			firstThursday = number
			break
		}
	}
	thursdayNumber, _ := core.DayNumber(thursday)
	index := (thursdayNumber-firstThursday)/7 + 1
	return ISOWeek{Name: fmt.Sprintf("%04d-W%02d", year, index), From: from, Until: until}
}

// WeekNamed is `2026-W43` to its Monday and Sunday; false for a name that is not a week.
func WeekNamed(name string) (ISOWeek, bool) {
	parts := strings.Split(name, "-W")
	if len(parts) != 2 {
		return ISOWeek{}, false
	}
	year, err1 := strconv.Atoi(parts[0])
	index, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil || index < 1 || index > 53 || year < 1970 || year > 9999 {
		return ISOWeek{}, false
	}
	// Week 1 holds January 4th.
	anchor := WeekContaining(fmt.Sprintf("%04d-01-04", year))
	monday, ok := core.AddingDays((index-1)*7, anchor.From)
	if !ok {
		return ISOWeek{}, false
	}
	found := WeekContaining(monday)
	if found.Name != fmt.Sprintf("%04d-W%02d", year, index) {
		return ISOWeek{}, false
	}
	return found, true
}
