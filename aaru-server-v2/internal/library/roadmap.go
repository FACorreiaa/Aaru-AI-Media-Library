package library

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"encoding/json"
	"fmt"
	"slices"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Roadmap is a list's steps (GRAPH-003): an order the owl planned in stages, kept beside the list's
// membership. The list's own order still decides the order inside a step.
type Roadmap struct {
	Steps []RoadmapStep `json:"steps"`
}

// RoadmapStep is one stage: a heading, a note, the titles in it, and what Aaru could not find, as text.
type RoadmapStep struct {
	Heading string        `json:"heading"`
	Note    string        `json:"note,omitempty"`
	Missing []string      `json:"missing,omitempty"`
	Items   []RoadmapItem `json:"items"`
}

// RoadmapItem is one member's place: its note ("FF #570-588"), whether it is optional, and the pair
// it is read side by side with (0 for none).
type RoadmapItem struct {
	TitleID  uuid.UUID `json:"titleId"`
	Note     string    `json:"note,omitempty"`
	Optional bool      `json:"optional,omitempty"`
	Pair     int       `json:"pair,omitempty"`
}

// Showing is the roadmap as the list stands: members removed by hand are left out, and a step left
// with nothing to show goes with them.
func (r Roadmap) Showing(members []uuid.UUID) Roadmap {
	out := Roadmap{Steps: []RoadmapStep{}}
	for _, step := range r.Steps {
		kept := step
		kept.Items = []RoadmapItem{}
		for _, item := range step.Items {
			if slices.Contains(members, item.TitleID) {
				kept.Items = append(kept.Items, item)
			}
		}
		if len(kept.Items) > 0 || len(kept.Missing) > 0 {
			out.Steps = append(out.Steps, kept)
		}
	}
	return out
}

// ListRoadmap is the list's roadmap; nil for a plain list.
func (s *Store) ListRoadmap(ctx context.Context, listID uuid.UUID) (*Roadmap, error) {
	raw, err := s.q.ListRoadmap(ctx, listID)
	if db.IsNoRows(err) {
		return nil, nil // nil: a plain list
	}
	if err != nil {
		return nil, fmt.Errorf("list roadmap: %w", err)
	}
	var r Roadmap
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("list roadmap: %w", err)
	}
	return &r, nil
}

// AppendRoadmapTx adds steps to the roadmap of the user's list of this name, inside an import's
// transaction: a new list gets them, a list that already had a roadmap gains them at its end. A list
// the import did not make (nothing matched) gets nothing.
func AppendRoadmapTx(ctx context.Context, tx pgx.Tx, user uuid.UUID, listName string, steps []RoadmapStep) error {
	if len(steps) == 0 {
		return nil
	}
	q := sqlc.New(tx)
	listID, err := q.ListIDByName(ctx, sqlc.ListIDByNameParams{UserID: user, Name: listName})
	if db.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("roadmap list: %w", err)
	}
	roadmap := Roadmap{Steps: []RoadmapStep{}}
	raw, err := q.ListRoadmap(ctx, listID)
	switch {
	case err == nil:
		if err := json.Unmarshal(raw, &roadmap); err != nil {
			return fmt.Errorf("list roadmap: %w", err)
		}
	case !db.IsNoRows(err):
		return fmt.Errorf("list roadmap: %w", err)
	}
	roadmap.Steps = append(roadmap.Steps, steps...)
	payload, err := json.Marshal(roadmap)
	if err != nil {
		return fmt.Errorf("encode roadmap: %w", err)
	}
	if err := q.PutListRoadmap(ctx, sqlc.PutListRoadmapParams{ListID: listID, Roadmap: payload}); err != nil {
		return fmt.Errorf("put roadmap: %w", err)
	}
	return nil
}
