package core

import (
	"aaru-go-api/internal/apperr"
	"fmt"
	"strconv"
)

// ValidationKind names why a value is not acceptable as Aaru data.
type ValidationKind int

// The validation failures.
const (
	EmptyTitle ValidationKind = iota + 1
	InvalidYear
	RatingOutOfRange
	RatingNotInHalfSteps
	EmptyListName
	InvalidEpisodeNumber
	InvalidBookProgress
	InvalidMangaProgress
	UnresolvableMediaRef
)

// ValidationError is why a value is not acceptable as Aaru data. Shared so the
// server and the clients reject the same inputs with the same words. It renders
// as 422 `validation_failed`, naming the offending request field.
type ValidationError struct {
	Kind ValidationKind
	// Year for InvalidYear.
	Year int
	// Value for the rating kinds.
	Value float64
	// Season and Episode for InvalidEpisodeNumber.
	Season, Episode int
}

func (e *ValidationError) Error() string {
	switch e.Kind {
	case EmptyTitle:
		return "Title text must not be empty."
	case InvalidYear:
		return fmt.Sprintf("Year %d is outside %d–%d.", e.Year, MinYear, MaxYear)
	case RatingOutOfRange:
		return fmt.Sprintf("Rating %s is outside %s–%s.", swiftDouble(e.Value), swiftDouble(RatingMin), swiftDouble(RatingMax))
	case RatingNotInHalfSteps:
		return fmt.Sprintf("Rating %s is not a multiple of %s.", swiftDouble(e.Value), swiftDouble(RatingStep))
	case EmptyListName:
		return "List name must not be empty."
	case InvalidEpisodeNumber:
		return fmt.Sprintf("Season %d episode %d is not a valid episode reference.", e.Season, e.Episode)
	case InvalidBookProgress:
		return "Book progress needs a non-negative page or a percent between 0 and 100."
	case InvalidMangaProgress:
		return "Manga progress needs a non-negative chapter or volume."
	case UnresolvableMediaRef:
		return "A media reference needs a title id, an external id, or a title and year."
	}
	return "Invalid value."
}

// Field is the request field a validation failure belongs to, for `ErrorResponse.details`.
func (e *ValidationError) Field() string {
	switch e.Kind {
	case EmptyTitle:
		return "title"
	case InvalidYear:
		return "year"
	case RatingOutOfRange, RatingNotInHalfSteps:
		return "rating"
	case EmptyListName:
		return "name"
	case InvalidEpisodeNumber:
		return "episode"
	case InvalidBookProgress, InvalidMangaProgress:
		return "progress"
	case UnresolvableMediaRef:
		return "mediaRef"
	}
	return "value"
}

// AppError maps the failure to 422 `validation_failed` (apperr.Convertible).
func (e *ValidationError) AppError() *apperr.Error {
	return apperr.Validation(e.Field(), e.Error())
}

// Is lets errors.Is compare two validation errors by value.
func (e *ValidationError) Is(target error) bool {
	t, ok := target.(*ValidationError)
	return ok && *t == *e
}

// swiftDouble formats a float as Swift's `Double.description` does for ordinary
// values: "11.0", "4.75", "-3.0".
func swiftDouble(v float64) string {
	s := strconv.FormatFloat(v, 'f', -1, 64)
	for _, c := range s {
		if c == '.' {
			return s
		}
	}
	return s + ".0"
}
