package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/mcp"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"

	"github.com/labstack/echo/v4"
)

// OUT-004 · the MCP route (`POST /v1/mcp`, MCPRoutes.swift) and its tools: internal/mcp is the
// transport, internal/agent the tools; this file decodes each tool's arguments as Swift's
// generated decoders did and answers with the same `/v1` DTOs the routes return.

// registerMCPRoutes adds `/v1/mcp`. It authenticates itself with an agent token.
func (s *Server) registerMCPRoutes(e *echo.Echo) {
	metadata := ""
	if s.OAuth != nil {
		metadata = s.OAuth.ResourceMetadataURL()
	} else if s.Config != nil && s.Config.PublicBaseURL != nil {
		metadata = strings.TrimSuffix(s.Config.PublicBaseURL.String(), "/") + "/.well-known/oauth-protected-resource/v1/mcp"
	}
	h := &mcp.Handler{Tokens: s.AgentTokens, Tools: mcpTools{s: s, tools: s.AgentTools()}, ResourceMetadataURL: metadata, Log: s.Log}
	h.Register(e)
}

// AgentTools is the outside agent's tool layer over this server's services.
func (s *Server) AgentTools() *agent.Tools {
	return &agent.Tools{
		Catalog: s.Catalog, Library: s.Library, Shelves: s.Shelves, Schedule: s.Schedule, Plans: s.Plans,
		Imports: s.AgentImports, Push: s.Push,
	}
}

type mcpTools struct {
	s     *Server
	tools *agent.Tools
}

func (m mcpTools) Call(ctx context.Context, name string, args json.RawMessage, caller auth.AgentCaller) (any, error) {
	switch name {
	case "search_titles":
		return m.searchTitles(ctx, args, caller)
	case "read_library":
		return m.readLibrary(ctx, args, caller)
	case "list_airs":
		return m.listAirs(ctx, args, caller)
	case "apply_library_patch":
		return m.applyLibraryPatch(ctx, args, caller)
	case "plan_import":
		return m.planImport(ctx, args, caller)
	}
	return nil, fmt.Errorf("mcp: no tool %q", name)
}

// MARK: Decoding

func decodeArgs(args json.RawMessage, v any) error {
	if err := json.Unmarshal(args, v); err != nil {
		return fmt.Errorf("%w: %w", mcp.ErrArguments, err)
	}
	return nil
}

var errArgs = mcp.ErrArguments

// wholeNumber is an Int as Swift read it through JSONValue: any JSON number with no fraction.
type wholeNumber int

func (n *wholeNumber) UnmarshalJSON(data []byte) error {
	var f float64
	if err := json.Unmarshal(data, &f); err != nil {
		return err
	}
	if f != math.Trunc(f) || math.Abs(f) > math.MaxInt32 {
		return fmt.Errorf("%v is not an integer", f)
	}
	*n = wholeNumber(f)
	return nil
}

func wholePtr(n *wholeNumber) *int {
	if n == nil {
		return nil
	}
	v := int(*n)
	return &v
}

func statusArg(raw *string) (*core.LibraryStatus, error) {
	if raw == nil {
		return nil, nil
	}
	s := core.LibraryStatus(*raw)
	if !s.Valid() {
		return nil, errArgs
	}
	return &s, nil
}

func mediaTypeArg(raw *string) (*core.MediaType, error) {
	if raw == nil {
		return nil, nil
	}
	t := core.MediaType(*raw)
	if !t.Valid() {
		return nil, errArgs
	}
	return &t, nil
}

// MARK: search_titles

type searchArgs struct {
	Query   *string `json:"query"`
	Type    *string `json:"type"`
	TitleID *string `json:"titleId"`
}

type searchResultDTO struct {
	Items      []api.CatalogHit `json:"items"`
	Incomplete bool             `json:"incomplete"`
}

func (m mcpTools) searchTitles(ctx context.Context, args json.RawMessage, caller auth.AgentCaller) (any, error) {
	var in searchArgs
	if err := decodeArgs(args, &in); err != nil {
		return nil, err
	}
	result, err := m.tools.SearchTitles(ctx, agent.SearchInput{Query: in.Query, Type: in.Type, TitleID: in.TitleID}, caller)
	if err != nil {
		return nil, err
	}
	if result.Detail != nil {
		return TitleDetailDTO(*result.Detail), nil
	}
	return searchResultDTO{Items: catalogHits(result.Hits), Incomplete: result.Incomplete}, nil
}

// MARK: read_library

type libraryArgs struct {
	LibraryItemID *string      `json:"libraryItemId"`
	Status        *string      `json:"status"`
	Type          *string      `json:"type"`
	Anime         *bool        `json:"anime"`
	Owned         *bool        `json:"owned"`
	ListID        *string      `json:"listId"`
	ShelfID       *string      `json:"shelfId"`
	Cursor        *string      `json:"cursor"`
	Limit         *wholeNumber `json:"limit"`
}

type libraryPageDTO struct {
	Items      []api.LibraryEntry `json:"items"`
	NextCursor *string            `json:"nextCursor,omitempty"`
}

func (m mcpTools) readLibrary(ctx context.Context, args json.RawMessage, caller auth.AgentCaller) (any, error) {
	var in libraryArgs
	if err := decodeArgs(args, &in); err != nil {
		return nil, err
	}
	status, err := statusArg(in.Status)
	if err != nil {
		return nil, err
	}
	typ, err := mediaTypeArg(in.Type)
	if err != nil {
		return nil, err
	}
	result, err := m.tools.ReadLibrary(ctx, agent.LibraryInput{
		LibraryItemID: in.LibraryItemID, Status: status, Type: typ, Anime: in.Anime, Owned: in.Owned, ListID: in.ListID,
		ShelfID: in.ShelfID, Cursor: in.Cursor, Limit: wholePtr(in.Limit),
	}, caller)
	if err != nil {
		return nil, err
	}
	if result.One != nil {
		return LibraryEntryWithWatchedDTO(ctx, m.s.Library.Store, *result.One)
	}
	return libraryPageDTO{Items: LibraryEntriesDTO(result.Items), NextCursor: result.NextCursor}, nil
}

// MARK: list_airs

type airsArgs struct {
	View *string `json:"view"`
	From *string `json:"from"`
	To   *string `json:"to"`
}

type calendarDTO struct {
	Items []api.CalendarEntry `json:"items"`
}

func (m mcpTools) listAirs(ctx context.Context, args json.RawMessage, caller auth.AgentCaller) (any, error) {
	var in airsArgs
	if err := decodeArgs(args, &in); err != nil {
		return nil, err
	}
	result, err := m.tools.ListAirs(ctx, agent.AirsInput{View: in.View, From: in.From, To: in.To}, caller)
	if err != nil {
		return nil, err
	}
	if result.UpNext != nil {
		return UpNextDTO(*result.UpNext), nil
	}
	return calendarDTO{Items: CalendarEntriesDTO(result.Calendar)}, nil
}

// MARK: apply_library_patch

type patchArgs struct {
	Changes *[]changeArgs `json:"changes"`
}

type episodeArgs struct {
	Season  *wholeNumber `json:"season"`
	Episode *wholeNumber `json:"episode"`
}

type mediaRefArgs struct {
	TitleID *apiid.UUID      `json:"titleId"`
	Type    *string          `json:"type"`
	IDs     *api.ExternalIds `json:"ids"`
	Title   *string          `json:"title"`
	Year    *wholeNumber     `json:"year"`
}

type itemPatchArgs struct {
	Status       *string      `json:"status"`
	Rating       *float64     `json:"rating"`
	Notes        *string      `json:"notes"`
	IsOwned      *bool        `json:"isOwned"`
	BookPage     *wholeNumber `json:"bookPage"`
	BookPercent  *float64     `json:"bookPercent"`
	MangaChapter *wholeNumber `json:"mangaChapter"`
	MangaVolume  *wholeNumber `json:"mangaVolume"`
	Clear        *[]string    `json:"clear"`
}

type changeArgs struct {
	Op            *string        `json:"op"`
	MediaRef      *mediaRefArgs  `json:"mediaRef"`
	Status        *string        `json:"status"`
	LibraryItemID *string        `json:"libraryItemId"`
	Patch         *itemPatchArgs `json:"patch"`
	Episodes      *[]episodeArgs `json:"episodes"`
	Season        *wholeNumber   `json:"season"`
	Watched       *bool          `json:"watched"`
}

func (r mediaRefArgs) ref() (core.MediaRef, error) {
	typ, err := mediaTypeArg(r.Type)
	if err != nil || typ == nil {
		return core.MediaRef{}, errArgs
	}
	return MediaRefFromAPI(api.MediaRef{
		TitleId: r.TitleID, Type: api.MediaType(*typ), Ids: r.IDs, Title: r.Title, Year: wholePtr(r.Year),
	}), nil
}

func (p itemPatchArgs) patch() (library.ItemPatch, error) {
	dto := api.LibraryItemPatch{
		Rating: p.Rating, Notes: p.Notes, IsOwned: p.IsOwned, BookPage: wholePtr(p.BookPage), BookPercent: p.BookPercent,
		MangaChapter: wholePtr(p.MangaChapter), MangaVolume: wholePtr(p.MangaVolume),
	}
	if p.Status != nil {
		if !core.LibraryStatus(*p.Status).Valid() {
			return library.ItemPatch{}, errArgs
		}
		st := api.LibraryStatus(*p.Status)
		dto.Status = &st
	}
	if p.Clear != nil {
		clear := make([]api.LibraryItemPatchClear, len(*p.Clear))
		for i, c := range *p.Clear {
			switch k := api.LibraryItemPatchClear(c); k {
			case api.LibraryItemPatchClearRating, api.LibraryItemPatchClearNotes, api.LibraryItemPatchClearBookProgress,
				api.LibraryItemPatchClearMangaProgress:
				clear[i] = k
			default:
				return library.ItemPatch{}, errArgs
			}
		}
		dto.Clear = &clear
	}
	return ItemPatchFromAPI(dto), nil
}

func (c changeArgs) change() (agent.PatchChange, error) {
	if c.Op == nil {
		return agent.PatchChange{}, errArgs
	}
	out := agent.PatchChange{Op: *c.Op, LibraryItemID: c.LibraryItemID, Season: wholePtr(c.Season), Watched: c.Watched}
	status, err := statusArg(c.Status)
	if err != nil {
		return agent.PatchChange{}, err
	}
	out.Status = status
	if c.MediaRef != nil {
		ref, err := c.MediaRef.ref()
		if err != nil {
			return agent.PatchChange{}, err
		}
		out.MediaRef = &ref
	}
	if c.Patch != nil {
		patch, err := c.Patch.patch()
		if err != nil {
			return agent.PatchChange{}, err
		}
		out.Patch = &patch
	}
	if c.Episodes != nil {
		out.Episodes = make([]agent.EpisodeInput, len(*c.Episodes))
		for i, ep := range *c.Episodes {
			if ep.Season == nil || ep.Episode == nil {
				return agent.PatchChange{}, errArgs
			}
			out.Episodes[i] = agent.EpisodeInput{Season: int(*ep.Season), Episode: int(*ep.Episode)}
		}
	}
	return out, nil
}

// planProposedDTO is a change bigger than a tap: nothing was written; the user decides in Aaru.
type planProposedDTO struct {
	Applied   bool         `json:"applied"`
	Status    string       `json:"status"`
	PlanID    string       `json:"planId"`
	Summary   string       `json:"summary"`
	Changes   int          `json:"changes"`
	ExpiresAt apitime.Time `json:"expiresAt"`
	Message   string       `json:"message"`
}

type patchAppliedDTO struct {
	Applied bool              `json:"applied"`
	Item    *api.LibraryEntry `json:"item,omitempty"`
}

func (m mcpTools) applyLibraryPatch(ctx context.Context, args json.RawMessage, caller auth.AgentCaller) (any, error) {
	var in patchArgs
	if err := decodeArgs(args, &in); err != nil {
		return nil, err
	}
	if in.Changes == nil {
		return nil, errArgs
	}
	changes := make([]agent.PatchChange, len(*in.Changes))
	for i, c := range *in.Changes {
		change, err := c.change()
		if err != nil {
			return nil, err
		}
		changes[i] = change
	}
	result, err := m.tools.ApplyLibraryPatch(ctx, agent.PatchInput{Changes: changes}, caller)
	if err != nil {
		return nil, err
	}
	if p := result.Plan; p != nil {
		return planProposedDTO{
			Applied: false, Status: "pending_approval", PlanID: strings.ToLower(p.ID.String()), Summary: p.Summary,
			Changes: len(p.Changes), ExpiresAt: apitime.From(p.ExpiresAt),
			Message: "Nothing has changed yet. The user was asked to approve this in Aaru; tell them it is waiting there.",
		}, nil
	}
	out := patchAppliedDTO{Applied: true}
	if result.Item != nil {
		item, err := LibraryEntryWithWatchedDTO(ctx, m.s.Library.Store, *result.Item)
		if err != nil {
			return nil, err
		}
		out.Item = &item
	}
	return out, nil
}

// MARK: plan_import

type importArgs struct {
	Text     *string `json:"text"`
	Filename *string `json:"filename"`
	Source   *string `json:"source"`
}

// importQueuedDTO is queued, never applied: Aaru matches the rows, then the user reviews and approves.
type importQueuedDTO struct {
	Applied  bool   `json:"applied"`
	Status   string `json:"status"`
	ImportID string `json:"importId"`
	Source   string `json:"source"`
	Message  string `json:"message"`
}

func (m mcpTools) planImport(ctx context.Context, args json.RawMessage, caller auth.AgentCaller) (any, error) {
	var in importArgs
	if err := decodeArgs(args, &in); err != nil {
		return nil, err
	}
	if in.Text == nil {
		return nil, errArgs
	}
	queued, err := m.tools.PlanImport(ctx, agent.ImportInput{Text: *in.Text, Filename: in.Filename, Source: in.Source}, caller)
	if err != nil {
		return nil, err
	}
	return importQueuedDTO{
		Applied: false, Status: "pending_approval", ImportID: strings.ToUpper(queued.ImportID.String()),
		Source: string(queued.Source),
		Message: "Nothing has changed yet. Aaru is matching the rows; the user reviews and approves the import in Aaru " +
			"(Settings → Imports). Tell them it is waiting there.",
	}, nil
}
