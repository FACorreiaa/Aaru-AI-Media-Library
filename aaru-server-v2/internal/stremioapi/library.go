package stremioapi

import (
	"encoding/json"
	"errors"
	"math"
)

var errNotInteger = errors.New("stremio: not an integer")

// LibraryItem is one item of a Stremio library, as `datastoreGet` returns it. Only the fields an
// import reads.
type LibraryItem struct {
	ID   string
	Type string
	Name string
	// Removed: taken out of the library by the user.
	Removed *bool
	// Temp: played but never added; Stremio keeps these for Continue watching.
	Temp  *bool
	State *LibraryState
}

// LibraryState is an item's watch state.
type LibraryState struct {
	LastWatched    *string
	TimeOffset     *int
	TimesWatched   *int
	FlaggedWatched *int
	// Watched is the watched-episode bitfield (see Episodes).
	Watched *string
}

// swiftInt is an Int as Swift's JSONDecoder read it: an integral number, 1200.0 included.
type swiftInt int

func (n *swiftInt) UnmarshalJSON(data []byte) error {
	var f float64
	if err := json.Unmarshal(data, &f); err != nil {
		return err //nolint:wrapcheck // a decode failure drops the item
	}
	if f != math.Trunc(f) || math.Abs(f) > math.MaxInt64/2 {
		return errNotInteger
	}
	*n = swiftInt(f)
	return nil
}

func intPtr(n *swiftInt) *int {
	if n == nil {
		return nil
	}
	v := int(*n)
	return &v
}

// decodeLibraryItem decodes one item as Swift's synthesized Codable did: `_id`, `type` and
// `name` required, every other field optional but of the right type. ok false drops the item.
func decodeLibraryItem(raw json.RawMessage) (LibraryItem, bool) {
	var wire struct {
		ID      *string `json:"_id"`
		Type    *string `json:"type"`
		Name    *string `json:"name"`
		Removed *bool   `json:"removed"`
		Temp    *bool   `json:"temp"`
		State   *struct {
			LastWatched    *string   `json:"lastWatched"`
			TimeOffset     *swiftInt `json:"timeOffset"`
			TimesWatched   *swiftInt `json:"timesWatched"`
			FlaggedWatched *swiftInt `json:"flaggedWatched"`
			Watched        *string   `json:"watched"`
		} `json:"state"`
	}
	if err := json.Unmarshal(raw, &wire); err != nil || wire.ID == nil || wire.Type == nil || wire.Name == nil {
		return LibraryItem{}, false
	}
	item := LibraryItem{ID: *wire.ID, Type: *wire.Type, Name: *wire.Name, Removed: wire.Removed, Temp: wire.Temp}
	if s := wire.State; s != nil {
		item.State = &LibraryState{
			LastWatched: s.LastWatched, TimeOffset: intPtr(s.TimeOffset), TimesWatched: intPtr(s.TimesWatched),
			FlaggedWatched: intPtr(s.FlaggedWatched), Watched: s.Watched,
		}
	}
	return item, true
}

// DecodeLibraryItem decodes one library item (tests, the export-file fallback).
func DecodeLibraryItem(raw []byte) (LibraryItem, bool) { return decodeLibraryItem(raw) }
