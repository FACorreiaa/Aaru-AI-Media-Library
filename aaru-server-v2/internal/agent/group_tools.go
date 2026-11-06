package agent

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/model"
	"context"
	"encoding/json"
	"strconv"
	"strings"
)

// GroupTools are the tools `@aaru` may call while answering one mention. All read; none writes.
// They are titleReads over the tagger's own library.
type GroupTools struct {
	titleReads
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
		Name: "read_my_library",
		Description: "The library of the person who tagged you (only theirs): titles with status and progress, " +
			"newest change first. Find one title by query.",
		InputSchema: schema(map[string]any{
			"status": map[string]any{
				"type": "string", "enum": []string{"wishlist", "in_progress", "on_hold", "finished", "dropped"},
			},
			"query": map[string]any{"type": "string", "description": "Part of a title's name."},
			"kind": map[string]any{
				"type": "string", "enum": []string{"movie", "show", "anime", "book", "manga", "album"},
			},
			"cursor": map[string]any{"type": "string", "description": "The cursor a page ended with, for the next one."},
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

// swiftDouble prints a number the way Swift prints a Double: 8.0, 7.5.
func swiftDouble(v float64) string {
	s := strconv.FormatFloat(v, 'f', -1, 64)
	if !strings.Contains(s, ".") {
		s += ".0"
	}
	return s
}
