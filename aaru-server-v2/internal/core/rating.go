package core

import (
	"encoding/json"
	"math"
	"strconv"
)

// The one rating scale: 1–10 in 0.5 steps. Do not introduce a second one —
// clients that display stars divide by two.
const (
	RatingMin  = 1.0
	RatingMax  = 10.0
	RatingStep = 0.5
)

// Rating is a user rating on Aaru's single, fixed scale.
type Rating float64

// NewRating rejects values off the scale or off the half-step grid.
func NewRating(value float64) (Rating, error) {
	if value < RatingMin || value > RatingMax || math.IsNaN(value) {
		return 0, &ValidationError{Kind: RatingOutOfRange, Value: value}
	}
	// Compare in half-step units to keep binary floating point out of the test.
	steps := math.Round(value / RatingStep)
	if math.Abs(steps*RatingStep-value) >= 0.0001 {
		return 0, &ValidationError{Kind: RatingNotInHalfSteps, Value: value}
	}
	return Rating(steps * RatingStep), nil
}

// Value is the rating as a number.
func (r Rating) Value() float64 { return float64(r) }

// String is "10" or "8.5".
func (r Rating) String() string {
	v := float64(r)
	if v == math.Round(v) {
		return strconv.Itoa(int(v))
	}
	return strconv.FormatFloat(v, 'f', -1, 64)
}

// UnmarshalJSON rejects a rating off the scale.
func (r *Rating) UnmarshalJSON(data []byte) error {
	var v float64
	if err := json.Unmarshal(data, &v); err != nil {
		return err
	}
	rating, err := NewRating(v)
	if err != nil {
		return err
	}
	*r = rating
	return nil
}
