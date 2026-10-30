// Package agent is AG-001's tools an outside agent reaches (Agent/AgentTools.swift,
// AgentTools+Import.swift), transport-neutral. Each one is a thin wrapper over the service a
// `/v1` route calls, with the caller's scopes checked first. MCP (internal/mcp, wired in
// internal/httpapi/mcp.go) is one transport over this.
//
// Swift's tools returned the `/v1` DTOs. Here they return domain values and the transport maps
// them with the same mappers the `/v1` routes use (httpapi), so no provider JSON leaks and this
// package does not depend on the HTTP layer.
//
// The API other areas call:
//
//   - Tools.SearchTitles / ReadLibrary / ListAirs / ApplyLibraryPatch / PlanImport.
//   - ParseChanges: apply_library_patch's input as validated plans.AgentChanges.
//   - Importer: what plan_import needs from the imports area (nil until it is wired).
//
// The `@aaru` group tools (GroupAgentTools) are a separate, read-only set and do not use these.
package agent

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/plans"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/schedule"
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

const (
	// MaxChanges is how many changes one apply_library_patch call may hold. A direct write is one
	// item and at most one episode, as a tap is (X-009); the rest become a plan.
	MaxChanges = 100
	// MaxLibraryPage is read_library's largest page.
	MaxLibraryPage = 50
	// MaxAirsDays is list_airs' longest calendar window.
	MaxAirsDays = 42
	// MaxImportBytes is plan_import's largest text (ImportService.maxUploadBytes).
	MaxImportBytes = 5 * 1024 * 1024
)

// ToolError is a tool call the caller cannot make, or made wrong; its message is for the agent.
type ToolError = plans.ToolError

func toolError(message string) error { return &plans.ToolError{Message: message} }

// errReadOnly is a write through a token without `library:write`.
var errReadOnly = toolError("This connection is read-only. The user can allow changes for it in Aaru → Settings → Connections.")

// Importer is what plan_import needs from the imports area (ImportService, ImportFormatDetector,
// CATCalendarParser). The imports port provides it; nil leaves plan_import answering that it could
// not finish.
type Importer interface {
	// DetectSource is ImportFormatDetector.detect: the file source the text is. When it cannot
	// tell, the error's message is the one shown to the user (ImportFormatError.message).
	DetectSource(text string) (core.ImportSource, error)
	// IsCATCalendar is CATCalendarParser.isCalendar: the text is an iCal file.
	IsCATCalendar(text string) bool
	// CreateFileImport is ImportService.createCSVImport: the text as an import job the user
	// reviews in Aaru before anything is applied. It returns the job's id.
	CreateFileImport(ctx context.Context, user uuid.UUID, source core.ImportSource, filename *string, text string) (uuid.UUID, error)
}

// Tools is the tool layer over the library, catalog and schedule services.
type Tools struct {
	Catalog  *catalog.Kit
	Library  *library.Service
	Shelves  *library.Shelves
	Schedule *schedule.Service
	Plans    *plans.Service
	// Imports is nil until the imports area wires it.
	Imports Importer
	// Push tells the user an import is waiting; nil sends nothing.
	Push *push.UserPush
	// Now defaults to time.Now.
	Now func() time.Time
}

func (t *Tools) now() time.Time {
	if t.Now == nil {
		return time.Now()
	}
	return t.Now()
}

func require(scope auth.Scope, caller auth.AgentCaller) error {
	if caller.Has(scope) {
		return nil
	}
	if scope == auth.ScopeLibraryWrite {
		return errReadOnly
	}
	return toolError("This connection cannot read the library.")
}

// parseUUID is Foundation's UUID(uuidString:): only the 36-character hyphenated form.
func parseUUID(raw string) (uuid.UUID, bool) {
	if len(raw) != 36 {
		return uuid.Nil, false
	}
	id, err := uuid.Parse(raw)
	return id, err == nil
}

// MARK: search_titles

// SearchInput is search_titles' arguments.
type SearchInput struct {
	Query   *string
	Type    *string
	TitleID *string
}

// SearchResult is a title's detail (by titleId) or a page of hits.
type SearchResult struct {
	Detail     *catalog.TitleDetail
	Hits       []catalog.Hit
	Incomplete bool
}

var searchScopes = map[string]catalog.SearchScope{
	"all": catalog.ScopeAll, "movie": catalog.ScopeMovie, "show": catalog.ScopeShow, "anime": catalog.ScopeAnime,
	"book": catalog.ScopeBook, "album": catalog.ScopeAlbum, "manga": catalog.ScopeManga,
}

// SearchTitles searches the public catalog, or reads one title's detail.
func (t *Tools) SearchTitles(ctx context.Context, in SearchInput, caller auth.AgentCaller) (SearchResult, error) {
	if err := require(auth.ScopeLibraryRead, caller); err != nil {
		return SearchResult{}, err
	}
	if in.TitleID != nil {
		if in.Query != nil {
			return SearchResult{}, toolError("Pass either query or titleId, not both.")
		}
		id, ok := parseUUID(*in.TitleID)
		if !ok {
			return SearchResult{}, toolError("That titleId is not valid.")
		}
		detail, err := t.Catalog.Service.Detail(ctx, id)
		if err != nil {
			return SearchResult{}, err
		}
		return SearchResult{Detail: detail}, nil
	}
	query := ""
	if in.Query != nil {
		query = strings.TrimSpace(*in.Query)
	}
	if n := utf8.RuneCountInString(query); n < 1 || n > 200 {
		return SearchResult{}, toolError("query must be 1 to 200 characters.")
	}
	name := "all"
	if in.Type != nil {
		name = *in.Type
	}
	scope, ok := searchScopes[name]
	if !ok {
		return SearchResult{}, toolError("type must be one of all, movie, show, anime, book.")
	}
	result, err := t.Catalog.Service.Search(ctx, query, scope)
	if err != nil {
		return SearchResult{}, err
	}
	return SearchResult{Hits: result.Hits, Incomplete: result.Incomplete}, nil
}

// MARK: read_library

// LibraryInput is read_library's arguments.
type LibraryInput struct {
	LibraryItemID *string
	Status        *core.LibraryStatus
	Type          *core.MediaType
	Anime         *bool
	Owned         *bool
	ListID        *string
	ShelfID       *string
	Cursor        *string
	Limit         *int
}

// LibraryResult is one item (with watched episodes, for a show) or a page.
type LibraryResult struct {
	One        *library.Entry
	Items      []library.Entry
	NextCursor *string
}

// ReadLibrary is one item by id, or a page under a filter or a shelf.
func (t *Tools) ReadLibrary(ctx context.Context, in LibraryInput, caller auth.AgentCaller) (LibraryResult, error) {
	if err := require(auth.ScopeLibraryRead, caller); err != nil {
		return LibraryResult{}, err
	}
	if in.LibraryItemID != nil {
		id, err := itemID(*in.LibraryItemID)
		if err != nil {
			return LibraryResult{}, err
		}
		entry, err := t.Library.Entry(ctx, id, caller.UserID)
		if err != nil {
			return LibraryResult{}, err
		}
		return LibraryResult{One: &entry}, nil
	}
	limit := 20
	if in.Limit != nil {
		limit = *in.Limit
	}
	if limit < 1 || limit > MaxLibraryPage {
		return LibraryResult{}, toolError("limit must be between 1 and " + strconv.Itoa(MaxLibraryPage) + ".")
	}
	if in.ShelfID != nil {
		shelf, ok := parseUUID(*in.ShelfID)
		if !ok {
			return LibraryResult{}, toolError("That shelfId is not valid.")
		}
		entries, next, err := t.Shelves.Items(ctx, shelf, caller.UserID, in.Cursor, limit)
		if err != nil {
			return LibraryResult{}, err
		}
		return LibraryResult{Items: entries, NextCursor: next}, nil
	}
	filter := library.Filter{Status: in.Status, Type: in.Type, IsAnime: in.Anime, IsOwned: in.Owned}
	if in.ListID != nil {
		list, ok := parseUUID(*in.ListID)
		if !ok {
			return LibraryResult{}, toolError("That listId is not valid.")
		}
		filter = filter.WithList(&list)
	}
	entries, next, err := t.Library.List(ctx, caller.UserID, filter, in.Cursor, limit)
	if err != nil {
		return LibraryResult{}, err
	}
	return LibraryResult{Items: entries, NextCursor: next}, nil
}

func itemID(raw string) (uuid.UUID, error) {
	id, ok := parseUUID(raw)
	if !ok {
		return uuid.Nil, toolError("That libraryItemId is not valid.")
	}
	return id, nil
}

// MARK: list_airs

// AirsInput is list_airs' arguments.
type AirsInput struct {
	View *string
	From *string
	To   *string
}

// AirsResult is Up Next, or the calendar's entries.
type AirsResult struct {
	UpNext   *schedule.UpNext
	Calendar []schedule.CalendarEntry
}

// ListAirs is the calendar of tracked shows, or Up Next as on Home.
func (t *Tools) ListAirs(ctx context.Context, in AirsInput, caller auth.AgentCaller) (AirsResult, error) {
	if err := require(auth.ScopeLibraryRead, caller); err != nil {
		return AirsResult{}, err
	}
	view := "calendar"
	if in.View != nil {
		view = *in.View
	}
	switch view {
	case "up_next":
		if in.From != nil || in.To != nil {
			return AirsResult{}, toolError("from and to apply to the calendar view only.")
		}
		upNext, err := t.Schedule.UpNext(ctx, caller.UserID)
		if err != nil {
			return AirsResult{}, err
		}
		return AirsResult{UpNext: &upNext}, nil
	case "calendar":
		from := t.now()
		if in.From != nil {
			parsed, err := ParseDate(*in.From, "from")
			if err != nil {
				return AirsResult{}, err
			}
			from = parsed
		}
		until := from.Add(7 * 24 * time.Hour)
		if in.To != nil {
			parsed, err := ParseDate(*in.To, "to")
			if err != nil {
				return AirsResult{}, err
			}
			until = parsed
		}
		if !until.After(from) || until.Sub(from) > MaxAirsDays*24*time.Hour {
			return AirsResult{}, toolError("to must be after from, and at most " + strconv.Itoa(MaxAirsDays) + " days later.")
		}
		entries, err := t.Schedule.Calendar(ctx, caller.UserID, from, until)
		if err != nil {
			return AirsResult{}, err
		}
		return AirsResult{Calendar: entries}, nil
	}
	return AirsResult{}, toolError("view must be calendar or up_next.")
}

// ParseDate reads `2026-10-20` (UTC midnight) or a full ISO 8601 date-time.
func ParseDate(raw, name string) (time.Time, error) {
	if !strings.Contains(raw, ".") {
		if t, err := time.Parse(time.RFC3339, raw); err == nil {
			return t, nil
		}
	}
	if t, err := time.Parse(time.DateOnly, raw); err == nil {
		return t, nil
	}
	return time.Time{}, toolError(name + " must be a date like 2026-10-20 or an ISO 8601 date-time.")
}

// MARK: apply_library_patch

// PatchInput is apply_library_patch's arguments (AgentPatchInput).
type PatchInput struct {
	Changes []PatchChange
}

// EpisodeInput is one episode in a change.
type EpisodeInput struct {
	Season  int
	Episode int
}

// PatchChange is one change as the agent sent it (AgentPatchChange). Episodes nil is absent; an
// empty, non-nil slice was sent as [].
type PatchChange struct {
	Op            string
	MediaRef      *core.MediaRef
	Status        *core.LibraryStatus
	LibraryItemID *string
	Patch         *library.ItemPatch
	Episodes      []EpisodeInput
	Season        *int
	Watched       *bool
}

// PatchResult is a change applied at once (Item nil after a removal), or a plan waiting for the
// user (Plan set, nothing written).
type PatchResult struct {
	Applied bool
	Item    *library.Entry
	Plan    *plans.Plan
}

// ApplyLibraryPatch applies one tap-sized change at once, journaled as the token; anything larger,
// and any removal, becomes a plan the user approves in Aaru.
func (t *Tools) ApplyLibraryPatch(ctx context.Context, in PatchInput, caller auth.AgentCaller) (PatchResult, error) {
	if err := require(auth.ScopeLibraryWrite, caller); err != nil {
		return PatchResult{}, err
	}
	changes, err := ParseChanges(in)
	if err != nil {
		return PatchResult{}, err
	}
	if len(changes) != 1 || !changes[0].IsTapSized() {
		plan, err := t.Plans.Propose(ctx, changes, caller)
		if err != nil {
			return PatchResult{}, err
		}
		return PatchResult{Plan: &plan}, nil
	}
	return t.apply(ctx, changes[0], caller)
}

// apply is one tap-sized change, journaled as the token.
func (t *Tools) apply(ctx context.Context, c plans.AgentChange, caller auth.AgentCaller) (PatchResult, error) {
	agent := library.AgentCaller(caller.Token)
	lib := t.Library
	user := caller.UserID
	var entry library.Entry
	switch c.Kind {
	case plans.ChangeAdd:
		e, err := lib.Add(ctx, c.Ref, c.Status, user, agent)
		if err != nil {
			return PatchResult{}, err
		}
		entry = e
	case plans.ChangeUpdate:
		e, err := lib.Patch(ctx, c.Item, user, c.Patch, agent)
		if err != nil {
			return PatchResult{}, err
		}
		entry = e
	case plans.ChangeEpisodes:
		switch {
		case c.Season != nil:
			w, err := lib.MarkSeasonWatched(ctx, c.Item, user, *c.Season, agent)
			if err != nil {
				return PatchResult{}, err
			}
			entry = w.Entry
		case len(c.Keys) == 1:
			// A single tick validates the episode, as the route does.
			w, err := lib.SetEpisode(ctx, c.Item, user, c.Keys[0], c.Watched, agent)
			if err != nil {
				return PatchResult{}, err
			}
			entry = w.Entry
		default:
			changed, err := lib.SetEpisodes(ctx, c.Item, user, c.Keys, c.Watched, agent)
			if err != nil {
				return PatchResult{}, err
			}
			if changed == nil {
				e, err := lib.Entry(ctx, c.Item, user)
				if err != nil {
					return PatchResult{}, err
				}
				changed = &e
			}
			entry = *changed
		}
	case plans.ChangeRemove:
		if err := lib.Delete(ctx, c.Item, user, agent); err != nil {
			return PatchResult{}, err
		}
		return PatchResult{Applied: true}, nil
	}
	return PatchResult{Applied: true, Item: &entry}, nil
}

// ParseChanges validates apply_library_patch's input (AgentChange.parse).
func ParseChanges(in PatchInput) ([]plans.AgentChange, error) {
	if len(in.Changes) < 1 || len(in.Changes) > MaxChanges {
		return nil, toolError("changes must hold 1 to " + strconv.Itoa(MaxChanges) + " entries.")
	}
	changes := make([]plans.AgentChange, len(in.Changes))
	for i, raw := range in.Changes {
		c, err := parseChange(raw, i)
		if err != nil {
			return nil, err
		}
		changes[i] = c
	}
	seen := map[uuid.UUID]bool{}
	for _, c := range changes {
		if id, ok := c.ItemID(); ok {
			if seen[id] {
				return nil, toolError("Each libraryItemId may appear once; combine its changes.")
			}
			seen[id] = true
		}
	}
	return changes, nil
}

func parseChange(in PatchChange, index int) (plans.AgentChange, error) {
	fail := func(message string) error {
		return toolError(fmt.Sprintf("changes[%d]: %s", index, message))
	}
	item := func() (uuid.UUID, error) {
		if in.LibraryItemID != nil {
			if id, ok := parseUUID(*in.LibraryItemID); ok {
				return id, nil
			}
		}
		return uuid.Nil, fail("needs a valid libraryItemId.")
	}
	switch in.Op {
	case "add":
		if in.MediaRef == nil {
			return plans.AgentChange{}, fail("add needs a mediaRef.")
		}
		return plans.AgentChange{Kind: plans.ChangeAdd, Ref: *in.MediaRef, Status: in.Status}, nil
	case "update":
		if in.Patch == nil {
			return plans.AgentChange{}, fail("update needs a patch.")
		}
		id, err := item()
		if err != nil {
			return plans.AgentChange{}, err
		}
		return plans.AgentChange{Kind: plans.ChangeUpdate, Item: id, Patch: *in.Patch}, nil
	case "episodes":
		id, err := item()
		if err != nil {
			return plans.AgentChange{}, err
		}
		return parseEpisodes(in, id, fail)
	case "remove":
		id, err := item()
		if err != nil {
			return plans.AgentChange{}, err
		}
		return plans.AgentChange{Kind: plans.ChangeRemove, Item: id}, nil
	}
	return plans.AgentChange{}, fail("op must be add, update, episodes or remove.")
}

func parseEpisodes(in PatchChange, id uuid.UUID, fail func(string) error) (plans.AgentChange, error) {
	if in.Watched == nil {
		return plans.AgentChange{}, fail("episodes needs watched: true or false.")
	}
	if in.Season != nil {
		if in.Episodes != nil || !*in.Watched {
			return plans.AgentChange{}, fail("season marks a whole season watched; pass either season or episodes.")
		}
		season := *in.Season
		return plans.AgentChange{Kind: plans.ChangeEpisodes, Item: id, Keys: []core.EpisodeKey{}, Season: &season, Watched: true}, nil
	}
	if len(in.Episodes) == 0 {
		return plans.AgentChange{}, fail("episodes needs a non-empty episodes list or a season.")
	}
	keys := make([]core.EpisodeKey, len(in.Episodes))
	for i, ep := range in.Episodes {
		k, err := core.NewEpisodeKey(ep.Season, ep.Episode)
		if err != nil {
			return plans.AgentChange{}, fail(fmt.Sprintf("S%dE%d is not a valid episode.", ep.Season, ep.Episode))
		}
		keys[i] = k
	}
	return plans.AgentChange{Kind: plans.ChangeEpisodes, Item: id, Keys: keys, Watched: *in.Watched}, nil
}

// MARK: plan_import

// ImportInput is plan_import's arguments.
type ImportInput struct {
	Text     string
	Filename *string
	Source   *string
}

// ImportQueued is an import job waiting for the user's review; nothing was applied.
type ImportQueued struct {
	ImportID uuid.UUID
	Source   core.ImportSource
}

// namedSources are the file sources the tool names directly.
var namedSources = map[string]core.ImportSource{
	"imdb": core.SourceIMDbCSV, "letterboxd": core.SourceLetterboxdCSV, "netflix": core.SourceNetflixCSV,
	"tvtime": core.SourceTVTimeCSV, "goodreads": core.SourceGoodreadsCSV, "mal": core.SourceMALXML,
	"csv": core.SourceGenericCSV,
}

// errNoImporter is plan_import before the imports area is wired: an internal failure.
var errNoImporter = errors.New("agent: no importer configured")

// PlanImport hands Aaru a list export as an ordinary import job, which the user reviews and
// approves in Aaru; it never writes the library.
func (t *Tools) PlanImport(ctx context.Context, in ImportInput, caller auth.AgentCaller) (ImportQueued, error) {
	if !caller.Has(auth.ScopeImportsWrite) {
		return ImportQueued{}, toolError("This connection cannot hand Aaru imports. The user can allow imports when " +
			"connecting it in Aaru → Settings → Connections.")
	}
	if len(in.Text) > MaxImportBytes {
		return ImportQueued{}, toolError("text is at most 5 MB.")
	}
	if t.Imports == nil {
		return ImportQueued{}, errNoImporter
	}
	name := "auto"
	if in.Source != nil {
		name = *in.Source
	}
	source, err := t.importSource(name, in.Text)
	if err != nil {
		return ImportQueued{}, err
	}
	job, err := t.Imports.CreateFileImport(ctx, caller.UserID, source, in.Filename, in.Text)
	if err != nil {
		return ImportQueued{}, err
	}
	t.Push.Send(ctx, push.Message{
		Title:   caller.Token.Name + " sent you an import",
		Body:    "Review it in Aaru before anything is added.",
		Payload: map[string]string{"importId": strings.ToUpper(job.String())},
	}, caller.UserID)
	return ImportQueued{ImportID: job, Source: source}, nil
}

// importSource is the tool's `source` argument as an import source; `auto` and `cat` look at the text.
func (t *Tools) importSource(name, text string) (core.ImportSource, error) {
	if source, ok := namedSources[name]; ok {
		return source, nil
	}
	switch name {
	case "cat":
		if t.Imports.IsCATCalendar(text) {
			return core.SourceCATICS, nil
		}
		return core.SourceCATList, nil
	case "auto":
		source, err := t.Imports.DetectSource(text)
		if err != nil {
			return "", toolError(err.Error())
		}
		return source, nil
	}
	return "", toolError("source must be auto, imdb, letterboxd, netflix, tvtime, goodreads, mal, csv or cat.")
}
