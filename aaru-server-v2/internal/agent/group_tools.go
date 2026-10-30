package agent

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/model"
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// GroupTools are the tools `@aaru` may call while answering one mention. All read; none writes.
//
// Titles reach the model as short refs (`r1`, `r2`, …) handed out by these tools, never as raw
// ids, so a card can only show a title a tool actually returned.
type GroupTools struct {
	Service *ReplyService
	Tagger  uuid.UUID
	refs    map[string]core.MediaRef
	// cards are the titles show_titles picked, in order, for the reply's cards.
	cards []core.Title
}

func schema(properties map[string]any, required []string) json.RawMessage {
	data, err := json.Marshal(map[string]any{
		"type": "object", "properties": properties, "required": required, "additionalProperties": false,
	})
	if err != nil {
		panic(err)
	}
	return data
}

// GroupToolDefinitions are the tools, always sent in full.
var GroupToolDefinitions = []model.Tool{
	{
		Name: "search_titles",
		Description: "Search the catalog for films, shows, anime, books or manga. " +
			"Returns refs to use with the other tools.",
		InputSchema: schema(map[string]any{
			"query": map[string]any{"type": "string"},
			"kind":  map[string]any{"type": "string", "enum": []string{"movie", "show", "anime", "book", "manga"}},
		}, []string{"query"}),
	},
	{
		Name:        "title_details",
		Description: "Facts about one title: year, synopsis, network, and for shows the status and episode count.",
		InputSchema: schema(map[string]any{"ref": map[string]any{"type": "string"}}, []string{"ref"}),
	},
	{
		Name:        "list_airs",
		Description: "The next episodes of a show to air, with dates.",
		InputSchema: schema(map[string]any{"ref": map[string]any{"type": "string"}}, []string{"ref"}),
	},
	{
		Name:        "read_my_library",
		Description: "The library of the person who tagged you (only theirs): titles with status and progress.",
		InputSchema: schema(map[string]any{
			"status": map[string]any{
				"type": "string", "enum": []string{"wishlist", "in_progress", "on_hold", "finished", "dropped"},
			},
		}, []string{}),
	},
	{
		Name:        "show_titles",
		Description: "Attach titles to your reply as cards. Use refs from the other tools.",
		InputSchema: schema(map[string]any{
			"refs": map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
		}, []string{"refs"}),
	},
}

// results runs every call in one assistant turn and answers them all in one user turn.
func (t *GroupTools) results(ctx context.Context, calls []model.ToolCall) model.Turn {
	blocks := make([]model.Block, len(calls))
	for i, call := range calls {
		output, isError := t.Run(ctx, call.Name, call.Input)
		blocks[i] = toolResult(call.ID, output, isError)
	}
	return model.Turn{Role: model.RoleUser, Content: blocks}
}

// Run runs one tool call. A failure becomes an error result the model can read, never an error.
func (t *GroupTools) Run(ctx context.Context, name string, input json.RawMessage) (string, bool) {
	var args map[string]any
	_ = json.Unmarshal(input, &args)
	var (
		out string
		err error
	)
	switch name {
	case "search_titles":
		out, err = t.search(ctx, args)
	case "title_details":
		out, err = t.details(ctx, args)
	case "list_airs":
		out, err = t.airs(ctx, args)
	case "read_my_library":
		out, err = t.myLibrary(ctx, args)
	case "show_titles":
		out, err = t.show(ctx, args)
	default:
		return "No tool called " + name + ".", true
	}
	if err != nil {
		return "That did not work: " + describeError(err), true
	}
	return out, false
}

func describeError(err error) string {
	if e := apperr.From(err); e != nil && e.Status < 500 {
		return e.Message
	}
	return err.Error()
}

func str(args map[string]any, key string) (string, bool) {
	v, ok := args[key].(string)
	return v, ok
}

// Cards are the titles show_titles picked.
func (t *GroupTools) Cards() []core.Title { return t.cards }

func (t *GroupTools) search(ctx context.Context, args map[string]any) (string, error) {
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
		result, err := t.Service.Catalog.Service.Search(ctx, query, scope)
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

func (t *GroupTools) details(ctx context.Context, args map[string]any) (string, error) {
	title, err := t.resolve(ctx, args)
	if err != nil {
		return "", err
	}
	lines := []string{DescribeTitle(title)}
	if title.Network != nil {
		lines = append(lines, "Network: "+*title.Network)
	}
	if title.Synopsis != nil {
		lines = append(lines, "Synopsis: "+truncate(*title.Synopsis, 500))
	}
	if title.Type == core.MediaShow {
		detail, err := t.Service.Catalog.Service.Detail(ctx, title.ID)
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

func (t *GroupTools) airs(ctx context.Context, args map[string]any) (string, error) {
	title, err := t.resolve(ctx, args)
	if err != nil {
		return "", err
	}
	if title.Type != core.MediaShow {
		return title.Title + " is not a show.", nil
	}
	now := t.Service.now()
	detail, err := t.Service.Catalog.Service.Detail(ctx, title.ID)
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
func (t *GroupTools) myLibrary(ctx context.Context, args map[string]any) (string, error) {
	var filter library.Filter
	if raw, ok := str(args, "status"); ok {
		if status := core.LibraryStatus(raw); status.Valid() {
			filter.Status = &status
		}
	}
	entries, _, err := t.Service.Library.List(ctx, t.Tagger, filter, nil, 60)
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

func (t *GroupTools) show(ctx context.Context, args map[string]any) (string, error) {
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
		title, err := t.Service.Catalog.Resolver().Resolve(ctx, media, nil)
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

func (t *GroupTools) remember(ref core.MediaRef) string {
	key := "r" + strconv.Itoa(len(t.refs)+1)
	t.refs[key] = ref
	return key
}

func (t *GroupTools) resolve(ctx context.Context, args map[string]any) (core.Title, error) {
	key, _ := str(args, "ref")
	ref, ok := t.refs[key]
	if !ok {
		return core.Title{}, apperr.NotFound("Unknown ref; use one a tool returned.")
	}
	return t.Service.Catalog.Resolver().Resolve(ctx, ref, nil)
}

// swiftDouble prints a number the way Swift prints a Double: 8.0, 7.5.
func swiftDouble(v float64) string {
	s := strconv.FormatFloat(v, 'f', -1, 64)
	if !strings.Contains(s, ".") {
		s += ".0"
	}
	return s
}
