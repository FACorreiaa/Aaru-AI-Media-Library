package agent

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// titleReads are the catalog and library reads `@aaru` in a group and a Chat with Aaru share. Both
// see only User's own library: no tool has a way to name anyone else.
//
// Titles reach the model as short refs (`r1`, `r2`, ...) handed out by these tools, never as raw
// ids, so a card can only show a title a tool actually returned.
type titleReads struct {
	Catalog *catalog.Kit
	Library *library.Service
	User    uuid.UUID
	// Now defaults to time.Now.
	Now  func() time.Time
	refs map[string]core.MediaRef
	// items are the library item ids read_my_library handed out, by the ref it gave each.
	items map[string]uuid.UUID
	// cards are the titles show_titles picked, in order, for the reply's cards.
	cards []core.Title
	// progress says how far User is in a title, for title_details. Nil leaves it out, as `@aaru` does.
	progress func(ctx context.Context, title uuid.UUID) (string, error)
}

func newTitleReads(kit *catalog.Kit, lib *library.Service, user uuid.UUID, now func() time.Time) titleReads {
	return titleReads{
		Catalog: kit, Library: lib, User: user, Now: now,
		refs: map[string]core.MediaRef{}, items: map[string]uuid.UUID{},
	}
}

func (t *titleReads) now() time.Time {
	if t.Now != nil {
		return t.Now()
	}
	return time.Now()
}

// Cards are the titles show_titles picked.
func (t *titleReads) Cards() []core.Title { return t.cards }

func (t *titleReads) search(ctx context.Context, args map[string]any) (string, error) {
	query, _ := str(args, "query")
	if query == "" {
		return "Give a query.", nil
	}
	scopes := []catalog.SearchScope{catalog.ScopeMovie, catalog.ScopeShow}
	if kind, ok := str(args, "kind"); ok {
		switch catalog.SearchScope(kind) {
		case catalog.ScopeMovie, catalog.ScopeShow, catalog.ScopeAnime, catalog.ScopeBook, catalog.ScopeManga,
			catalog.ScopeAll, catalog.ScopeAlbum:
			scopes = []catalog.SearchScope{catalog.SearchScope(kind)}
		}
	}
	var lines []string
	for _, scope := range scopes {
		result, err := t.Catalog.Service.Search(ctx, query, scope)
		if err != nil {
			return "", err
		}
		for _, hit := range result.Hits[:min(len(result.Hits), 5)] {
			ref := t.remember(hit.MediaRef())
			kind := string(hit.Type)
			if hit.IsAnime {
				kind = "anime"
			}
			year := ""
			if hit.Year != nil {
				year = fmt.Sprintf(" (%d)", *hit.Year)
			}
			overview := ""
			if hit.Overview != nil {
				overview = " — " + truncate(*hit.Overview, 160)
			}
			lines = append(lines, fmt.Sprintf("%s: %s%s [%s]%s", ref, hit.Title, year, kind, overview))
		}
	}
	if len(lines) == 0 {
		return "Nothing found.", nil
	}
	return strings.Join(lines, "\n"), nil
}

func (t *titleReads) details(ctx context.Context, args map[string]any) (string, error) {
	title, err := t.resolve(ctx, args)
	if err != nil {
		return "", err
	}
	lines := []string{DescribeTitle(title)}
	if t.progress != nil {
		// Read first: a synopsis must not go out with nothing to guard it.
		line, err := t.progress(ctx, title.ID)
		if err != nil {
			return "", err
		}
		lines = append(lines, line)
	}
	if title.Network != nil {
		lines = append(lines, "Network: "+*title.Network)
	}
	if title.Synopsis != nil {
		lines = append(lines, "Synopsis: "+truncate(*title.Synopsis, 500))
	}
	if title.Type == core.MediaShow {
		detail, err := t.Catalog.Service.Detail(ctx, title.ID)
		if err != nil {
			return "", err
		}
		seasons := map[int]bool{}
		for _, ep := range detail.Episodes {
			if ep.Season > 0 {
				seasons[ep.Season] = true
			}
		}
		status := "unknown"
		if detail.Status != nil {
			status = string(*detail.Status)
		}
		lines = append(lines, fmt.Sprintf("Status: %s, %d seasons, %d episodes", status, len(seasons), len(detail.Episodes)))
	}
	return strings.Join(lines, "\n"), nil
}

func (t *titleReads) airs(ctx context.Context, args map[string]any) (string, error) {
	title, err := t.resolve(ctx, args)
	if err != nil {
		return "", err
	}
	if title.Type != core.MediaShow {
		return title.Title + " is not a show.", nil
	}
	now := t.now()
	detail, err := t.Catalog.Service.Detail(ctx, title.ID)
	if err != nil {
		return "", err
	}
	var upcoming []catalog.Episode
	for _, ep := range detail.Episodes {
		if ep.AirsAt != nil && ep.AirsAt.After(now) {
			upcoming = append(upcoming, ep)
		}
	}
	sort.SliceStable(upcoming, func(i, j int) bool { return upcoming[i].AirsAt.Before(*upcoming[j].AirsAt) })
	upcoming = upcoming[:min(len(upcoming), 5)]
	if len(upcoming) == 0 {
		return "No upcoming episodes are known for " + title.Title + ".", nil
	}
	lines := make([]string, len(upcoming))
	for i, ep := range upcoming {
		name := ""
		if ep.Name != nil {
			name = *ep.Name
		}
		lines[i] = fmt.Sprintf("S%dE%d %s: %s", ep.Season, ep.Episode, name, ep.AirsAt.UTC().Format(time.DateOnly))
	}
	return strings.Join(lines, "\n"), nil
}

// myLibrary is the tagger's library only: the tool has no way to name anyone else.
func (t *titleReads) myLibrary(ctx context.Context, args map[string]any) (string, error) {
	var filter library.Filter
	if raw, ok := str(args, "status"); ok {
		if status := core.LibraryStatus(raw); status.Valid() {
			filter.Status = &status
		}
	}
	entries, _, err := t.Library.List(ctx, t.User, filter, nil, 60)
	if err != nil {
		return "", err
	}
	if len(entries) == 0 {
		return "Their library has nothing here.", nil
	}
	lines := make([]string, len(entries))
	for i, e := range entries {
		id := e.Title.ID
		ref := t.remember(core.MediaRef{TitleID: &id, Type: e.Title.Type})
		t.items[ref] = e.Item.ID
		line := ref + ": " + DescribeTitle(e.Title) + " — " + string(e.Item.Status)
		if e.Progress != nil {
			line += fmt.Sprintf(", %d/%d episodes", e.Progress.WatchedCount, e.Progress.AiredCount)
		}
		if e.Item.Rating != nil {
			line += ", rated " + swiftDouble(e.Item.Rating.Value()) + "/10"
		}
		lines[i] = line
	}
	return strings.Join(lines, "\n"), nil
}

func (t *titleReads) show(ctx context.Context, args map[string]any) (string, error) {
	items, ok := args["refs"].([]any)
	if !ok {
		return "Give refs.", nil
	}
	var shown []string
	for _, item := range items {
		if len(t.cards) >= MaxCards {
			break
		}
		key, ok := item.(string)
		if !ok {
			continue
		}
		media, ok := t.refs[key]
		if !ok {
			continue
		}
		title, err := t.Catalog.Resolver().Resolve(ctx, media, nil)
		if err != nil {
			return "", err
		}
		dup := false
		for _, c := range t.cards {
			if c.ID == title.ID {
				dup = true
			}
		}
		if !dup {
			t.cards = append(t.cards, title)
			shown = append(shown, title.Title)
		}
	}
	if len(shown) == 0 {
		return "No cards added; use refs the tools gave you.", nil
	}
	return "Shown: " + strings.Join(shown, ", "), nil
}

func (t *titleReads) remember(ref core.MediaRef) string {
	key := "r" + strconv.Itoa(len(t.refs)+1)
	t.refs[key] = ref
	return key
}

func (t *titleReads) resolve(ctx context.Context, args map[string]any) (core.Title, error) {
	key, _ := str(args, "ref")
	ref, ok := t.refs[key]
	if !ok {
		return core.Title{}, apperr.NotFound("Unknown ref; use one a tool returned.")
	}
	return t.Catalog.Resolver().Resolve(ctx, ref, nil)
}
