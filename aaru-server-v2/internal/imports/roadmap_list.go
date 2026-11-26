package imports

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/google/uuid"
)

// ownRoadmapLists gives every roadmap in the plan a list of its own (ASK-012): a roadmap whose name
// one of the user's lists already has is renamed "Name (2)", "Name (3)" and so on, on every row
// that names it, so asking for the same roadmap twice makes a second list instead of doubling the
// first one's steps. Lists without a roadmap (shelves, plain orders) still join a list of their
// name. It runs at approval, so two plans of one name approved one after the other each get their own
// list, and the renamed rows are saved with the plan, so the import's list is found by its new name.
// It reads the lists before the approval's transaction, as listOps does: two approvals of one name
// at the same instant can still both take the name.
func (s *Service) ownRoadmapLists(ctx context.Context, rows []PlannedRow, user uuid.UUID) error {
	var names []string
	for _, r := range rows {
		if r.Row.Roadmap == nil || isTrue(r.Row.LeftOut) {
			continue
		}
		for _, list := range r.Row.Lists {
			if !slices.Contains(names, list) {
				names = append(names, list)
			}
		}
	}
	if len(names) == 0 {
		return nil
	}
	existing, err := s.Library.Lists(ctx, user)
	if err != nil {
		return fmt.Errorf("roadmap lists: %w", err)
	}
	slices.Sort(names)
	renamed := map[string]string{}
	for _, name := range names {
		free := freeListName(existing, name)
		if free == name {
			continue
		}
		renamed[name] = free
		existing = append(existing, core.AaruList{Name: free})
	}
	if len(renamed) == 0 {
		return nil
	}
	for i := range rows {
		lists := slices.Clone(rows[i].Row.Lists)
		for j, list := range lists {
			if free, ok := renamed[list]; ok {
				lists[j] = free
			}
		}
		rows[i].Row.Lists = lists
	}
	return nil
}

// freeListName is name when none of the lists has it (case aside), else the first of "name (2)",
// "name (3)"… that none has, with name cut so the whole fits a list name (capture.MaxListName, in
// runes, as capture.ListName counts them).
func freeListName(existing []core.AaruList, name string) string {
	taken := func(candidate string) bool {
		return slices.ContainsFunc(existing, func(l core.AaruList) bool { return strings.EqualFold(l.Name, candidate) })
	}
	if !taken(name) {
		return name
	}
	for n := 2; ; n++ {
		suffix := fmt.Sprintf(" (%d)", n)
		base := []rune(name)
		base = base[:min(len(base), capture.MaxListName-len(suffix))]
		candidate := strings.TrimSpace(string(base)) + suffix
		if !taken(candidate) {
			return candidate
		}
	}
}
