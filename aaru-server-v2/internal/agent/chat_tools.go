package agent

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/model"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/plans"
	"aaru-go-api/internal/social"
	"aaru-go-api/internal/sports"
	"aaru-go-api/internal/stats"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"strings"

	"github.com/google/uuid"
)

const (
	// ChatListTitles is how many titles of one list read_my_lists names.
	ChatListTitles = 30
	// ChatLists is how many lists read_my_lists names.
	ChatLists = 20
	// ChatListens is how many listens read_my_listens names.
	ChatListens = 50
	// ChatTopTitles is how many titles read_my_stats names.
	ChatTopTitles = 5
)

// ChatDeps are the services a Chat with Aaru reads and writes through. A nil Sports leaves
// read_my_sports out; every other one is required.
type ChatDeps struct {
	// Q reads the caller's progress in a title.
	Q         *sqlc.Queries
	Tools     *Tools
	Stats     *stats.Service
	Lists     *library.Store
	Favorites *social.Service
	Music     *music.Service
	Sports    *sports.Service
	// TitleLists plans a list the user asked for (BOOK-003). Nil leaves the tool out.
	TitleLists TitleListPlanner
	// Files hands a chat's file to an import (ASK-010). Nil leaves import_attachment out.
	Files FileImporter
}

// TitleListPlanner turns titles chosen in a chat into a capture the user reviews in Aaru, matched and
// shown like any other. It never writes the library. Implemented by imports.AgentImporter.
type TitleListPlanner interface {
	CreateTitleList(ctx context.Context, user uuid.UUID, titles []capture.Title, list string) (uuid.UUID, error)
}

// ChatTools are the tools a signed-in user's Chat with Aaru may call: the shared title reads, a
// read over each area of their own data, and the library write. Every read is of User and nobody
// else; no tool has a way to name anyone else. One value serves one Chat turn.
type ChatTools struct {
	titleReads
	deps ChatDeps

	plan          *plans.Plan
	importID      *uuid.UUID
	applied       bool
	actionID      *uuid.UUID
	actionSummary string

	// attachments are the chat's files by ref (a1, a2, …). Any at all taints the turn: every write
	// is then a plan, since the words in a file were not typed by the user (ASK-010).
	attachments map[string]Attachment
	tainted     bool
}

// NewChatTools builds the tools for one Chat turn of user.
func NewChatTools(deps ChatDeps, user uuid.UUID) *ChatTools {
	reads := newTitleReads(deps.Tools.Catalog, deps.Tools.Library, user, deps.Tools.Now)
	reads.progress = func(ctx context.Context, title core.Title) (string, error) {
		return spoilerGuard(ctx, deps.Q, title, user)
	}
	return &ChatTools{titleReads: reads, deps: deps}
}

// spoilerGuard says how far user is in a title and what that keeps the model from saying. Only a title
// with no library row is "not started": a book being read has a status and no episode to point at.
func spoilerGuard(ctx context.Context, q *sqlc.Queries, title core.Title, user uuid.UUID) (string, error) {
	progress, err := groups.ProgressOf(ctx, q, title.ID, user)
	if err != nil {
		return "", fmt.Errorf("chat title progress: %w", err)
	}
	if progress != nil && progress.Status != core.StatusFinished && progress.Furthest == nil {
		return "Their library has it as \"" + library.StatusLabel(progress.Status, title.Type) + "\", with no episode marked. " +
			"Do not reveal anything that happens in it unless they say how far they are.", nil
	}
	return "They have " + DescribeProgress(progress) + ". Do not reveal anything that happens after that point.", nil
}

// Plan is the plan apply_library_patch proposed this turn, for the user to approve in Aaru.
func (t *ChatTools) Plan() *plans.Plan { return t.plan }

// ImportID is the capture this turn's plan_title_list started, for its review.
func (t *ChatTools) ImportID() *uuid.UUID { return t.importID }

// ActionID is the journaled action of this turn's applied write, for Undo.
func (t *ChatTools) ActionID() *uuid.UUID { return t.actionID }

// ActionSummary is what the journal says that action did; empty when there is none.
func (t *ChatTools) ActionSummary() string { return t.actionSummary }

// Definitions are the tools to send, in full every round.
func (t *ChatTools) Definitions() []model.Tool {
	out := make([]model.Tool, 0, len(GroupToolDefinitions)+6)
	for _, d := range GroupToolDefinitions {
		switch d.Name {
		case "read_my_library":
			d.Description = "The signed-in user's own library: titles with status and progress, newest change first. " +
				"Find one title by query. A line's ref also names its library item for apply_library_patch."
		case "title_details":
			d.Description += " Also how far the user is in it."
		}
		out = append(out, d)
	}
	out = append(out,
		model.Tool{
			Name: "read_my_stats",
			Description: "The user's watching and reading stats for one period: finished counts, time, " +
				"top titles and genres. The current month unless asked.",
			InputSchema: schema(map[string]any{
				"span":  map[string]any{"type": "string", "enum": []string{"month", "year", "last7", "last30", "all"}},
				"year":  map[string]any{"type": "integer"},
				"month": map[string]any{"type": "integer", "minimum": 1, "maximum": 12},
			}, []string{}),
		},
		model.Tool{
			Name:        "read_my_lists",
			Description: "The user's lists: names with their titles.",
			InputSchema: schema(map[string]any{}, []string{}),
		},
		model.Tool{
			Name:        "read_my_favorites",
			Description: "The user's top 10 favorites for each kind.",
			InputSchema: schema(map[string]any{}, []string{}),
		},
		model.Tool{
			Name:        "read_my_listens",
			Description: "The user's latest music listens, newest first.",
			InputSchema: schema(map[string]any{}, []string{}),
		},
	)
	if t.deps.Sports != nil {
		out = append(out, model.Tool{
			Name:        "read_my_sports",
			Description: "The leagues, teams and players the user follows, with what is live and next.",
			InputSchema: schema(map[string]any{}, []string{}),
		})
	}
	if t.deps.TitleLists != nil {
		out = append(out, model.Tool{
			Name: "plan_title_list",
			Description: "Send several titles the user asked to have added, or an order to read or watch them in, as one " +
				"list: real, published titles, at most 50, in order, with list_name when there is an order. For a roadmap " +
				"(\"what should I read before X\"), give steps with a heading each, put every title in its step, give " +
				"issue or episode ranges as its note, mark extras optional, and give titles read side by side the same " +
				"pair. Aaru matches them and the user reviews them in Aaru; nothing is added until they approve. Once per reply.",
			InputSchema: capture.Tool.InputSchema,
		})
	}
	if t.deps.Files != nil && len(t.attachments) > 0 {
		out = append(out, importAttachmentTool)
	}
	return append(out, model.Tool{
		Name: "apply_library_patch",
		Description: "Change the user's library. One item and at most one episode applies at once, as a tap does " +
			"and the user can undo it, once per reply; anything larger, and any removal, becomes a request the user " +
			"approves in Aaru. Put everything the user asked for in one call. " +
			"Never say something changed unless the answer says Applied. Add by a ref from search_titles; " +
			"update, episodes and remove take a ref from read_my_library.",
		InputSchema: schema(map[string]any{
			"changes": map[string]any{
				"type": "array", "minItems": 1, "maxItems": MaxChanges,
				"items": schema(map[string]any{
					"op":  map[string]any{"type": "string", "enum": []string{"add", "update", "episodes", "remove"}},
					"ref": map[string]any{"type": "string"},
					"status": map[string]any{
						"type": "string", "enum": []string{"wishlist", "in_progress", "on_hold", "finished", "dropped"},
					},
					"rating":   map[string]any{"type": "number", "minimum": 0, "maximum": 10},
					"notes":    map[string]any{"type": "string"},
					"is_owned": map[string]any{"type": "boolean"},
					"watched":  map[string]any{"type": "boolean"},
					"season":   map[string]any{"type": "integer"},
					"episodes": map[string]any{"type": "array", "items": schema(map[string]any{
						"season": map[string]any{"type": "integer"}, "episode": map[string]any{"type": "integer"},
					}, []string{"season", "episode"})},
				}, []string{"op", "ref"}),
			},
		}, []string{"changes"}),
	})
}

// results runs every call in one assistant turn and answers them all in one user turn.
func (t *ChatTools) results(ctx context.Context, calls []model.ToolCall) model.Turn {
	blocks := make([]model.Block, len(calls))
	for i, call := range calls {
		output, isError := t.Run(ctx, call.Name, call.Input)
		blocks[i] = toolResult(call.ID, output, isError)
	}
	return model.Turn{Role: model.RoleUser, Content: blocks}
}

// Run runs one tool call. A failure becomes an error result the model can read, never an error.
func (t *ChatTools) Run(ctx context.Context, name string, input json.RawMessage) (string, bool) {
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
	case "read_my_stats":
		out, err = t.readStats(ctx, args)
	case "read_my_lists":
		out, err = t.readLists(ctx)
	case "read_my_favorites":
		out, err = t.readFavorites(ctx)
	case "read_my_listens":
		out, err = t.readListens(ctx)
	case "read_my_sports":
		if t.deps.Sports == nil {
			return "No tool called " + name + ".", true
		}
		out, err = t.readSports(ctx)
	case "plan_title_list":
		if t.deps.TitleLists == nil {
			return "No tool called " + name + ".", true
		}
		out, err = t.planTitleList(ctx, input)
	case "apply_library_patch":
		out, err = t.patch(ctx, input)
	case "import_attachment":
		if t.deps.Files == nil || len(t.attachments) == 0 {
			return "No tool called " + name + ".", true
		}
		out, err = t.importAttachment(ctx, input)
	default:
		return "No tool called " + name + ".", true
	}
	if err != nil {
		if errors.Is(err, ErrCaptureQuota) {
			return strings.TrimPrefix(err.Error(), ErrCaptureQuota.Error()+": "), true
		}
		return "That did not work: " + describeError(err), true
	}
	return out, false
}

func plural(n int, one, many string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, one)
	}
	return fmt.Sprintf("%d %s", n, many)
}

// MARK: read_my_stats

func (t *ChatTools) readStats(ctx context.Context, args map[string]any) (string, error) {
	now := t.now()
	var (
		span        *stats.Span
		year, month *int
	)
	if raw, ok := str(args, "span"); ok && raw != "" && raw != string(stats.SpanMonth) && raw != string(stats.SpanYear) {
		s := stats.Span(raw)
		span = &s
	} else {
		y, m := now.Year(), int(now.Month())
		if v, ok := args["year"].(float64); ok {
			y = int(v)
		}
		year = &y
		if raw != string(stats.SpanYear) {
			if v, ok := args["month"].(float64); ok {
				m = int(v)
			}
			month = &m
		}
	}
	res, err := t.deps.Stats.Stats(ctx, t.User, span, year, month, nil)
	if err != nil {
		return "", err
	}
	label := string(res.Period.Span)
	switch {
	case month != nil:
		label = fmt.Sprintf("%04d-%02d", *year, *month)
	case year != nil:
		label = fmt.Sprintf("%d", *year)
	}
	tot := res.Totals
	lines := []string{
		fmt.Sprintf("Period: %s (%s to %s)", label, res.Period.Start, res.Period.End),
		fmt.Sprintf("%s watched, %d minutes, %s active",
			plural(tot.EpisodesWatched, "episode", "episodes"), tot.MinutesWatched, plural(tot.ActiveDays, "day", "days")),
		strings.Join([]string{
			plural(tot.MoviesFinished, "movie", "movies") + " finished",
			plural(tot.ShowsFinished, "show", "shows") + " finished",
			plural(tot.AnimeFinished, "anime", "anime") + " finished",
			plural(tot.BooksFinished, "book", "books") + " finished",
			plural(tot.MangaFinished, "manga", "manga") + " finished",
			plural(tot.AlbumsFinished, "album", "albums") + " finished",
		}, ", "),
	}
	for _, top := range res.TopTitles[:min(len(res.TopTitles), ChatTopTitles)] {
		lines = append(lines, fmt.Sprintf("Top: %s, %s, %d minutes",
			DescribeTitle(top.Title), plural(top.Episodes, "episode", "episodes"), top.Minutes))
	}
	if res.Ratings.Count > 0 && res.Ratings.Mean != nil {
		lines = append(lines, fmt.Sprintf("Rated %d titles, mean %s/10", res.Ratings.Count, swiftDouble(*res.Ratings.Mean)))
	}
	genres := make([]string, 0, 3)
	for _, g := range res.TopGenres[:min(len(res.TopGenres), 3)] {
		genres = append(genres, g.Name)
	}
	if len(genres) > 0 {
		lines = append(lines, "Top genres: "+strings.Join(genres, ", "))
	}
	if res.Music != nil {
		lines = append(lines, "Listens: "+plural(res.Music.Listens, "listen", "listens"))
	}
	return strings.Join(lines, "\n"), nil
}

// MARK: read_my_lists

func (t *ChatTools) readLists(ctx context.Context) (string, error) {
	lists, err := t.deps.Lists.Lists(ctx, t.User)
	if err != nil {
		return "", err
	}
	if len(lists) == 0 {
		return "They have no lists.", nil
	}
	lists = lists[:min(len(lists), ChatLists)]
	var ids []uuid.UUID
	for _, l := range lists {
		ids = append(ids, l.TitleIDs[:min(len(l.TitleIDs), ChatListTitles)]...)
	}
	byID := map[uuid.UUID]core.Title{}
	if len(ids) > 0 {
		titles, err := t.Catalog.Store.Titles(ctx, ids)
		if err != nil {
			return "", err
		}
		for _, title := range titles {
			byID[title.ID] = title
		}
	}
	lines := make([]string, len(lists))
	for i, l := range lists {
		var names []string
		for _, id := range l.TitleIDs[:min(len(l.TitleIDs), ChatListTitles)] {
			if title, ok := byID[id]; ok {
				names = append(names, DescribeTitle(title))
			}
		}
		lines[i] = fmt.Sprintf("%s (%s)", l.Name, plural(len(l.TitleIDs), "title", "titles"))
		if len(names) > 0 {
			lines[i] += ": " + strings.Join(names, "; ")
		}
	}
	return strings.Join(lines, "\n"), nil
}

// MARK: read_my_favorites

func (t *ChatTools) readFavorites(ctx context.Context) (string, error) {
	favs, err := t.deps.Favorites.Favorites(ctx, t.User)
	if err != nil {
		return "", err
	}
	kinds := make([]string, 0, len(favs))
	for kind, titles := range favs {
		if len(titles) > 0 {
			kinds = append(kinds, string(kind))
		}
	}
	if len(kinds) == 0 {
		return "They have no favorites yet.", nil
	}
	slices.Sort(kinds)
	lines := make([]string, len(kinds))
	for i, kind := range kinds {
		names := make([]string, len(favs[social.FavoriteKind(kind)]))
		for j, title := range favs[social.FavoriteKind(kind)] {
			names[j] = fmt.Sprintf("%d. %s", j+1, DescribeTitle(title))
		}
		lines[i] = kind + ": " + strings.Join(names, "; ")
	}
	return strings.Join(lines, "\n"), nil
}

// MARK: read_my_listens

func (t *ChatTools) readListens(ctx context.Context) (string, error) {
	limit := ChatListens
	listens, err := t.deps.Music.Listens(ctx, t.User, nil, &limit)
	if err != nil {
		return "", err
	}
	if len(listens) == 0 {
		return "They have no listens yet.", nil
	}
	lines := make([]string, 0, len(listens))
	for _, l := range listens[:min(len(listens), ChatListens)] {
		line := l.ListenedAt.UTC().Format("2006-01-02 15:04") + ": " + l.Artist + " - " + l.Track
		if l.Album != nil {
			line += " (" + *l.Album + ")"
		}
		lines = append(lines, line)
	}
	return strings.Join(lines, "\n"), nil
}

// MARK: read_my_sports

func (t *ChatTools) readSports(ctx context.Context) (string, error) {
	favs, err := t.deps.Sports.Favorites(ctx, t.User)
	if err != nil {
		return "", err
	}
	if len(favs.Items) == 0 {
		return "They follow nothing yet.", nil
	}
	lines := make([]string, len(favs.Items))
	for i, f := range favs.Items {
		line := fmt.Sprintf("%s (%s, %s)", f.Entity.Name, f.Entity.Kind, f.Entity.Sport)
		for _, e := range f.Live {
			line += "; live: " + describeSportEvent(e)
		}
		if f.Next != nil {
			line += "; next: " + describeSportEvent(*f.Next)
		}
		if f.Pending {
			line += "; fixtures are still loading"
		}
		lines[i] = line
	}
	if favs.Unavailable {
		lines = append(lines, "Fixtures are not available right now.")
	}
	return strings.Join(lines, "\n"), nil
}

func describeSportEvent(e sports.Event) string {
	name := e.Name
	if e.Home != nil && e.Away != nil {
		name = e.Home.Name + " v " + e.Away.Name
	}
	switch {
	case e.StartsAt != nil:
		name += " " + e.StartsAt.UTC().Format("2006-01-02 15:04 UTC")
	case e.Day != "":
		name += " " + e.Day
	}
	return name
}

// MARK: plan_title_list

// planTitleList is BOOK-003: the titles as a capture to review. One a reply.
func (t *ChatTools) planTitleList(ctx context.Context, input json.RawMessage) (string, error) {
	if t.importID != nil {
		return "These titles are already waiting for the user's review. Tell them that.", nil
	}
	titles := capture.Rows(input)
	if len(titles) == 0 {
		return "No titles to plan. Send at least one.", nil
	}
	id, err := t.deps.TitleLists.CreateTitleList(ctx, t.User, titles, capture.ListName(input))
	if err != nil {
		return "", err
	}
	t.importID = &id
	return plural(len(titles), "title", "titles") + " sent. Aaru is matching them, then they wait for the user's review. " +
		"Nothing is added until they approve. Tell them that.", nil
}

// MARK: apply_library_patch

type patchArgs struct {
	Changes []struct {
		Op       string   `json:"op"`
		Ref      string   `json:"ref"`
		Status   *string  `json:"status"`
		Rating   *float64 `json:"rating"`
		Notes    *string  `json:"notes"`
		IsOwned  *bool    `json:"is_owned"`
		Watched  *bool    `json:"watched"`
		Season   *int     `json:"season"`
		Episodes []struct {
			Season  int `json:"season"`
			Episode int `json:"episode"`
		} `json:"episodes"`
	} `json:"changes"`
}

// patchInput reads the tool's input as a PatchInput, naming titles and items by the refs the
// other tools handed out. A ref nobody handed out is the model's mistake, said so it can try again.
func (t *ChatTools) patchInput(raw json.RawMessage) (PatchInput, error) {
	var args patchArgs
	if err := json.Unmarshal(raw, &args); err != nil {
		return PatchInput{}, toolError("changes must be a list of changes.")
	}
	in := PatchInput{Changes: make([]PatchChange, len(args.Changes))}
	for i, c := range args.Changes {
		change := PatchChange{Op: c.Op, Season: c.Season, Watched: c.Watched}
		if c.Status != nil {
			status := core.LibraryStatus(*c.Status)
			if !status.Valid() {
				return PatchInput{}, toolError(fmt.Sprintf("changes[%d]: unknown status.", i))
			}
			change.Status = &status
		}
		if c.Op == "add" {
			ref, ok := t.refs[c.Ref]
			if !ok {
				return PatchInput{}, toolError(fmt.Sprintf("changes[%d]: unknown ref; add by a ref search_titles returned.", i))
			}
			change.MediaRef = &ref
		} else {
			item, ok := t.items[c.Ref]
			if !ok {
				return PatchInput{}, toolError(fmt.Sprintf("changes[%d]: unknown ref; use a ref read_my_library returned.", i))
			}
			id := item.String()
			change.LibraryItemID = &id
		}
		if c.Op == "update" {
			change.Patch = &library.ItemPatch{Status: change.Status, Rating: c.Rating, Notes: c.Notes, IsOwned: c.IsOwned}
		}
		if c.Episodes != nil {
			change.Episodes = make([]EpisodeInput, len(c.Episodes))
			for j, ep := range c.Episodes {
				change.Episodes[j] = EpisodeInput{Season: ep.Season, Episode: ep.Episode}
			}
		}
		in.Changes[i] = change
	}
	return in, nil
}

// errOneTapPerTurn is a second tap-sized change in one turn. A turn offers one Undo, so "mark A, B
// and C as watched" must not become three writes with an Undo for the last.
var errOneTapPerTurn = toolError("Nothing was changed by this call: one single change already went through in this " +
	"reply, and only one can. Put all the remaining changes in one apply_library_patch call so the user can " +
	"approve them together. If only one remains, tell the user it was not made and that they can ask again.")

// errOnePlanPerTurn is any change after a plan in one turn. The card shows one plan, so a second
// would wait unseen in Aaru and hold another capture.
var errOnePlanPerTurn = toolError("Nothing was changed by this call: this reply already has a request for the user " +
	"to approve, and it can only have one. Tell the user to review that request, and that they can ask for the rest after.")

func (t *ChatTools) patch(ctx context.Context, raw json.RawMessage) (string, error) {
	if t.plan != nil {
		return "", errOnePlanPerTurn
	}
	in, err := t.patchInput(raw)
	if err != nil {
		return "", err
	}
	if t.applied {
		tap, err := IsTapSizedPatch(in)
		if err != nil {
			return "", err
		}
		if tap {
			return "", errOneTapPerTurn
		}
	}
	patch := t.deps.Tools.ChatPatch
	if t.tainted {
		patch = t.deps.Tools.ChatPatchPlanned
	}
	res, err := patch(ctx, in, t.User)
	if err != nil {
		return "", err
	}
	if res.Plan != nil {
		t.plan = res.Plan
		return "This needs approval in Aaru: " + res.Plan.Summary +
			". Nothing has changed yet. Tell the user to review the request in Aaru.", nil
	}
	t.applied = true
	if res.ActionID != nil {
		t.actionID = res.ActionID
		t.actionSummary = t.summaryOf(ctx, *res.ActionID)
	}
	if res.Item == nil {
		return "Applied: removed from the library.", nil
	}
	return "Applied: " + DescribeTitle(res.Item.Title) + " is now " + string(res.Item.Item.Status) + ".", nil
}

// summaryOf is the journal's own words for an action. A failed read only loses the words.
func (t *ChatTools) summaryOf(ctx context.Context, id uuid.UUID) string {
	actions, err := t.Library.Store.Actions(ctx, t.User, 10)
	if err != nil {
		slog.WarnContext(ctx, "summary of a chat write", "error", err)
		return ""
	}
	for _, a := range actions {
		if a.ID == id {
			return a.Summary
		}
	}
	return ""
}
