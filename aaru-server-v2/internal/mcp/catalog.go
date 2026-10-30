package mcp

import (
	"slices"
	"strconv"
)

// The tool limits the schemas advertise (AgentTools' constants).
const (
	maxChanges     = 100
	maxLibraryPage = 50
	maxAirsDays    = 42
)

// Tool is one advertised tool (MCPTool). Schemas are strict (`additionalProperties: false`) and
// unknown top-level arguments are rejected server-side too, so a typo is never ignored.
type Tool struct {
	Name        string
	Title       string
	Description string
	InputSchema map[string]any
	// Writes false promises the tool changes nothing the user would notice.
	Writes      bool
	Destructive bool
}

// Definition is the tool as `tools/list` shows it.
func (t Tool) Definition() map[string]any {
	return map[string]any{
		"name":        t.Name,
		"title":       t.Title,
		"description": t.Description,
		"inputSchema": t.InputSchema,
		"annotations": map[string]any{
			"title":           t.Title,
			"readOnlyHint":    !t.Writes,
			"destructiveHint": t.Destructive,
			"idempotentHint":  !t.Writes,
			"openWorldHint":   false,
		},
	}
}

// UnknownArgument is the first argument (in sorted order) the schema does not name, if any.
func (t Tool) UnknownArgument(names []string) (string, bool) {
	properties, ok := t.InputSchema["properties"].(map[string]any)
	if !ok {
		return "", false
	}
	sorted := slices.Clone(names)
	slices.Sort(sorted)
	for _, name := range sorted {
		if _, known := properties[name]; !known {
			return name, true
		}
	}
	return "", false
}

// Catalog is AG-001's tools over MCP: exactly the tool layer (internal/agent), nothing more.
var Catalog = []Tool{searchTitles, readLibrary, listAirs, applyLibraryPatch, planImport}

// ToolNamed is the tool with this name.
func ToolNamed(name string) (Tool, bool) {
	for _, t := range Catalog {
		if t.Name == name {
			return t, true
		}
	}
	return Tool{}, false
}

// Listing is every tool's definition, in order.
func Listing() []any {
	out := make([]any, len(Catalog))
	for i, t := range Catalog {
		out[i] = t.Definition()
	}
	return out
}

var statuses = []string{"wishlist", "in_progress", "on_hold", "finished", "dropped"}

var searchTitles = Tool{
	Name:  "search_titles",
	Title: "Search the catalog",
	Description: "Search movies, shows, anime, books and albums in the public catalog, or read one title's detail " +
		"(episodes included for shows) by titleId. To add a hit, pass {\"type\": hit.type, \"ids\": hit.ids} " +
		"as the mediaRef of an apply_library_patch add.",
	InputSchema: object(map[string]any{
		"query": str("Words to search for, 1 to 200 characters."),
		"type": enumeration(
			[]string{"all", "movie", "show", "anime", "book", "album", "manga"},
			"What to search. all is films, shows and anime together; books only with book, albums only with "+
				"album, manga only with manga.",
		),
		"titleId": str("An Aaru title id, to read that title's detail instead of searching."),
	}),
}

var readLibrary = Tool{
	Name:  "read_library",
	Title: "Read the library",
	Description: "The user's library, newest change first: one item by libraryItemId (with watched episodes for " +
		"shows), or a page filtered by status, type, anime, owned, a list or a pinned shelf. Pass " +
		"nextCursor back as cursor for the next page.",
	InputSchema: object(map[string]any{
		"libraryItemId": str("One item's id. Other filters are ignored."),
		"status": enumeration(statuses,
			"wishlist is plan to watch, read or listen; in_progress is watching, reading or listening; "+
				"on_hold is on hold, paused on purpose."),
		"type":    enumeration([]string{"movie", "show", "book", "album", "manga"}, "Only this kind of title."),
		"anime":   map[string]any{"type": "boolean", "description": "Only anime, or no anime."},
		"owned":   map[string]any{"type": "boolean", "description": "Only titles the user owns."},
		"listId":  str("Only items on this list."),
		"shelfId": str("The items of this saved shelf instead of a filter."),
		"cursor":  str("nextCursor from the previous page."),
		"limit": map[string]any{
			"type": "integer", "minimum": 1, "maximum": maxLibraryPage, "default": 20,
		},
	}),
}

var listAirs = Tool{
	Name:  "list_airs",
	Title: "What airs and what's next",
	Description: "calendar: episodes of shows the user tracks airing between from and to (default the next 7 " +
		"days, at most " + strconv.Itoa(maxAirsDays) + "). up_next: what to continue, what to start, library " +
		"counts and unfinished shows, as on the user's Home.",
	InputSchema: object(map[string]any{
		"view": enumeration([]string{"calendar", "up_next"}, "Defaults to calendar."),
		"from": str("Start, as 2026-10-20 or an ISO 8601 date-time. Defaults to now."),
		"to":   str("End, exclusive. Defaults to 7 days after from."),
	}),
}

var applyLibraryPatch = Tool{
	Name:  "apply_library_patch",
	Title: "Change the library",
	Description: "Add titles, update status, rating, notes or ownership, tick episodes, or remove items. A " +
		"single change to one item (at most one episode) applies at once and the user can undo it in " +
		"Aaru. Anything larger, and any removal, is sent to the user to approve in Aaru and answers " +
		"applied: false with a planId. Needs a connection the user allowed to make changes.",
	InputSchema: object(map[string]any{
		"changes": map[string]any{
			"type":     "array",
			"minItems": 1,
			"maxItems": maxChanges,
			"items":    change,
		},
	}, "changes"),
	Writes:      true,
	Destructive: true,
}

var planImport = Tool{
	Name:  "plan_import",
	Title: "Hand Aaru a list to import",
	Description: "Give Aaru a list export (IMDb, Letterboxd, Netflix viewing activity, TV Time or Goodreads CSV, " +
		"MyAnimeList XML, a Pogdesign CAT iCal file or show list with source cat, or any CSV with title columns) " +
		"as text. Aaru matches every row and the user reviews and approves the import in Aaru; this tool never " +
		"changes the library itself. Needs a connection the user allowed imports for.",
	InputSchema: object(map[string]any{
		"text":     str("The file's contents, at most 5 MB."),
		"filename": str("The file's name, if it has one. Helps tell formats apart."),
		"source": enumeration(
			[]string{"auto", "imdb", "letterboxd", "netflix", "tvtime", "goodreads", "mal", "csv", "cat"},
			"Defaults to auto: detected from the text. A plain list of show names needs cat.",
		),
	}, "text"),
	Writes: true,
}

var change = map[string]any{
	"type": "object",
	"description": "One change. op add needs mediaRef ({type, ids} from a search hit) and may set status; update needs " +
		"libraryItemId and patch; episodes needs libraryItemId, watched, and episodes or a season (a " +
		"whole season marks every aired episode watched); remove needs libraryItemId.",
	"required":             []any{"op"},
	"additionalProperties": false,
	"properties": map[string]any{
		"op": enumeration([]string{"add", "update", "episodes", "remove"}, ""),
		"mediaRef": map[string]any{
			"type":        "object",
			"description": "{type, ids} copied from a search hit, or {type, titleId}.",
			"required":    []any{"type"},
			"properties": map[string]any{
				"type":    enumeration([]string{"movie", "show", "book", "album", "manga"}, ""),
				"ids":     map[string]any{"type": "object"},
				"titleId": str(""),
				"title":   str(""),
				"year":    map[string]any{"type": "integer"},
			},
		},
		"status":        enumeration(statuses, ""),
		"libraryItemId": str(""),
		"patch": map[string]any{
			"type":                 "object",
			"additionalProperties": false,
			"properties": map[string]any{
				"status": enumeration(statuses, ""),
				"rating": map[string]any{
					"type": "number", "minimum": 0.5, "maximum": 5,
					"description": "Half steps from 0.5 to 5.",
				},
				"notes":        str(""),
				"isOwned":      map[string]any{"type": "boolean"},
				"bookPage":     map[string]any{"type": "integer", "minimum": 0},
				"bookPercent":  map[string]any{"type": "number", "minimum": 0, "maximum": 100},
				"mangaChapter": map[string]any{"type": "integer", "minimum": 0},
				"mangaVolume":  map[string]any{"type": "integer", "minimum": 0},
				"clear": map[string]any{
					"type":  "array",
					"items": enumeration([]string{"rating", "notes", "bookProgress", "mangaProgress"}, ""),
				},
			},
		},
		"episodes": map[string]any{
			"type": "array",
			"items": object(map[string]any{
				"season":  map[string]any{"type": "integer", "minimum": 0},
				"episode": map[string]any{"type": "integer", "minimum": 1},
			}, "season", "episode"),
		},
		"season":  map[string]any{"type": "integer", "minimum": 0},
		"watched": map[string]any{"type": "boolean"},
	},
}

// MARK: Schema helpers

func object(properties map[string]any, required ...string) map[string]any {
	req := make([]any, len(required))
	for i, r := range required {
		req[i] = r
	}
	return map[string]any{
		"type":                 "object",
		"properties":           properties,
		"required":             req,
		"additionalProperties": false,
	}
}

// str is a string schema; an empty description is left out.
func str(description string) map[string]any {
	s := map[string]any{"type": "string"}
	if description != "" {
		s["description"] = description
	}
	return s
}

// enumeration is a string enum schema; an empty description is left out.
func enumeration(values []string, description string) map[string]any {
	vals := make([]any, len(values))
	for i, v := range values {
		vals[i] = v
	}
	s := map[string]any{"type": "string", "enum": vals}
	if description != "" {
		s["description"] = description
	}
	return s
}
