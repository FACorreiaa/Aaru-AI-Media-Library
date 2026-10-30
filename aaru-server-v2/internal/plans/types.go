// Package plans is AG-003's remote slice (OUT-004, Plans/*.swift): an outside agent's library
// change bigger than a tap is worked out now, against the library as it is, and stored as a plan.
// Only the user, signed in, approves or denies it; no agent token reaches the plan routes, so no
// caller approves its own plan.
//
// The API other areas call:
//
//   - AgentChange and ToolError: one validated library change an agent asked for, and a tool
//     failure whose message is safe to hand the agent. internal/agent parses tool input into
//     AgentChanges and applies tap-sized ones itself; the rest go to Service.Propose.
//   - Service.Propose / Plans / Plan / Approve / Deny.
//
// Plans are stored in `agent_plans` in the encoding the Swift server wrote (Foundation's default
// JSONEncoder over Swift's synthesized Codable: property names as keys, uppercase UUIDs), so
// either server can read or approve a plan the other stored.
package plans

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ToolError is a tool call the caller cannot make, or made wrong (AgentToolError). The message
// is safe to show the agent, which will repeat it to the user.
type ToolError struct{ Message string }

func (e *ToolError) Error() string { return e.Message }

// ToolMessage is what the agent is told.
func (e *ToolError) ToolMessage() string { return e.Message }

// Status is where a plan stands.
type Status string

// The plan statuses.
const (
	StatusPending Status = "pending"
	StatusApplied Status = "applied"
	StatusDenied  Status = "denied"
	StatusStale   Status = "stale"
	StatusExpired Status = "expired"
)

func (s Status) valid() bool {
	switch s {
	case StatusPending, StatusApplied, StatusDenied, StatusStale, StatusExpired:
		return true
	}
	return false
}

// Change is one line of the plan as the user reads it (AgentPlan.Change).
type Change struct {
	Text      string
	TitleID   uuid.UUID
	Title     string
	Type      core.MediaType
	PosterURL *string
	// LibraryItemID is nil for an add: the item does not exist yet.
	LibraryItemID *uuid.UUID
}

// Counts are how many of each kind of change a plan holds.
type Counts struct {
	Adds     int `json:"adds"`
	Updates  int `json:"updates"`
	Removes  int `json:"removes"`
	Episodes int `json:"episodes"`
}

// Basis is what the library looked like when the plan was made. Approval checks it again, so a
// plan never lands on a library that moved under it.
type Basis struct {
	// Items is each touched item's `updated_at` in microseconds, by lowercase item id.
	Items map[string]int64
	// AbsentTitles are titles the plan adds, which must still be absent.
	AbsentTitles []uuid.UUID
}

// Plan is a change an outside agent asked for that is bigger than a tap (AgentPlan). It waits in
// Aaru until the user approves or denies it; nothing is written before that.
type Plan struct {
	ID           uuid.UUID
	AgentTokenID *uuid.UUID
	AgentName    string
	Status       Status
	Summary      string
	Changes      []Change
	Counts       Counts
	Op           library.Op
	Basis        Basis
	CreatedAt    time.Time
	ExpiresAt    time.Time
	DecidedAt    *time.Time
	ActionID     *uuid.UUID
}

// IsExpired is pending, but past its expiry: it can no longer be approved.
func (p Plan) IsExpired(now time.Time) bool {
	return p.Status == StatusPending && !p.ExpiresAt.After(now)
}

// ChangeKind is what an AgentChange does.
type ChangeKind int

// The change kinds.
const (
	ChangeAdd ChangeKind = iota + 1
	ChangeUpdate
	ChangeEpisodes
	ChangeRemove
)

// AgentChange is one library change an agent asked for, validated. Tap-sized changes apply at
// once; the rest wait for the user (X-009).
type AgentChange struct {
	Kind ChangeKind
	// Ref and Status are an add's title and status (nil: wishlist).
	Ref    core.MediaRef
	Status *core.LibraryStatus
	// Item is the item an update, episodes or remove change touches.
	Item  uuid.UUID
	Patch library.ItemPatch
	// Keys are the episodes to tick, or (with Season) none: every aired episode of that season.
	Keys    []core.EpisodeKey
	Season  *int
	Watched bool
}

// ItemID is the item the change touches; false for an add.
func (c AgentChange) ItemID() (uuid.UUID, bool) {
	if c.Kind == ChangeAdd {
		return uuid.Nil, false
	}
	return c.Item, true
}

// IsTapSized is what a single tap could do: one item, at most one episode, and never a removal.
func (c AgentChange) IsTapSized() bool {
	switch c.Kind {
	case ChangeAdd, ChangeUpdate:
		return true
	case ChangeEpisodes:
		return c.Season == nil && len(c.Keys) == 1
	}
	return false
}

// MARK: Stored JSON

// swiftUUID is a UUID as Foundation encodes it: uppercase. It reads any case.
type swiftUUID uuid.UUID

func (u swiftUUID) MarshalJSON() ([]byte, error) {
	return json.Marshal(strings.ToUpper(uuid.UUID(u).String()))
}

func (u *swiftUUID) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return err
	}
	id, err := uuid.Parse(s)
	if err != nil {
		return fmt.Errorf("plan uuid: %w", err)
	}
	*u = swiftUUID(id)
	return nil
}

type storedChange struct {
	Text          string         `json:"text"`
	TitleID       swiftUUID      `json:"titleID"`
	Title         string         `json:"title"`
	Type          core.MediaType `json:"type"`
	PosterURL     *string        `json:"posterURL,omitempty"`
	LibraryItemID *swiftUUID     `json:"libraryItemID,omitempty"`
}

// storedChanges is the `changes` column: one object, because Swift bound an array as `jsonb[]`.
type storedChanges struct {
	Items []storedChange `json:"items"`
}

type storedBasis struct {
	Items        map[string]int64 `json:"items"`
	AbsentTitles []swiftUUID      `json:"absentTitles"`
}

func encodeChanges(changes []Change) (json.RawMessage, error) {
	out := storedChanges{Items: make([]storedChange, len(changes))}
	for i, c := range changes {
		s := storedChange{Text: c.Text, TitleID: swiftUUID(c.TitleID), Title: c.Title, Type: c.Type, PosterURL: c.PosterURL}
		if c.LibraryItemID != nil {
			id := swiftUUID(*c.LibraryItemID)
			s.LibraryItemID = &id
		}
		out.Items[i] = s
	}
	return json.Marshal(out)
}

func decodeChanges(data []byte) ([]Change, error) {
	var stored storedChanges
	if err := json.Unmarshal(data, &stored); err != nil {
		return nil, fmt.Errorf("plan changes: %w", err)
	}
	out := make([]Change, len(stored.Items))
	for i, s := range stored.Items {
		c := Change{Text: s.Text, TitleID: uuid.UUID(s.TitleID), Title: s.Title, Type: s.Type, PosterURL: s.PosterURL}
		if s.LibraryItemID != nil {
			id := uuid.UUID(*s.LibraryItemID)
			c.LibraryItemID = &id
		}
		out[i] = c
	}
	return out, nil
}

func encodeBasis(b Basis) (json.RawMessage, error) {
	s := storedBasis{Items: b.Items, AbsentTitles: make([]swiftUUID, len(b.AbsentTitles))}
	if s.Items == nil {
		s.Items = map[string]int64{}
	}
	for i, id := range b.AbsentTitles {
		s.AbsentTitles[i] = swiftUUID(id)
	}
	return json.Marshal(s)
}

func decodeBasis(data []byte) (Basis, error) {
	var s storedBasis
	if err := json.Unmarshal(data, &s); err != nil {
		return Basis{}, fmt.Errorf("plan basis: %w", err)
	}
	b := Basis{Items: s.Items, AbsentTitles: make([]uuid.UUID, len(s.AbsentTitles))}
	if b.Items == nil {
		b.Items = map[string]int64{}
	}
	for i, id := range s.AbsentTitles {
		b.AbsentTitles[i] = uuid.UUID(id)
	}
	return b, nil
}
