package mcp

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNegotiate(t *testing.T) {
	v := "2025-03-26"
	assert.Equal(t, v, Negotiate(&v))
	old := "2024-11-05"
	assert.Equal(t, "2025-11-25", Negotiate(&old))
	assert.Equal(t, "2025-11-25", Negotiate(nil))
}

func TestCatalogShape(t *testing.T) {
	var names []string
	for _, tool := range Catalog {
		names = append(names, tool.Name)
	}
	assert.Equal(t, []string{"search_titles", "read_library", "list_airs", "apply_library_patch", "plan_import"}, names)

	data, err := json.Marshal(Listing())
	require.NoError(t, err)
	var listed []map[string]any
	require.NoError(t, json.Unmarshal(data, &listed))
	read := listed[1]
	assert.Equal(t, map[string]any{
		"title": "Read the library", "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false,
	}, read["annotations"])
	schema := read["inputSchema"].(map[string]any)
	assert.Equal(t, []any{}, schema["required"], "an empty required list is still sent")
	assert.Equal(t, false, schema["additionalProperties"])
	assert.Equal(t, map[string]any{"type": "integer", "minimum": 1.0, "maximum": 50.0, "default": 20.0},
		schema["properties"].(map[string]any)["limit"])

	patch := listed[3]
	assert.Equal(t, true, patch["annotations"].(map[string]any)["destructiveHint"])
	assert.Equal(t, []any{"changes"}, patch["inputSchema"].(map[string]any)["required"])
	imp := listed[4]
	assert.Equal(t, false, imp["annotations"].(map[string]any)["destructiveHint"])
	assert.Equal(t, false, imp["annotations"].(map[string]any)["readOnlyHint"])
	change := patch["inputSchema"].(map[string]any)["properties"].(map[string]any)["changes"].(map[string]any)["items"].(map[string]any)
	op := change["properties"].(map[string]any)["op"].(map[string]any)
	_, hasDescription := op["description"]
	assert.False(t, hasDescription, "a nil description is left out")
}

func TestUnknownArgumentIsTheFirstSorted(t *testing.T) {
	tool, ok := ToolNamed("read_library")
	require.True(t, ok)
	name, found := tool.UnknownArgument([]string{"zeta", "status", "alpha"})
	assert.True(t, found)
	assert.Equal(t, "alpha", name)
	_, found = tool.UnknownArgument([]string{"status", "limit"})
	assert.False(t, found)
}

func TestParse(t *testing.T) {
	for _, body := range []string{`[]`, `null`, `{"id":1}`, `{"id":1,"method":null}`, `{"id":1,"method":2}`, `{"jsonrpc":2,"id":1,"method":"ping"}`, `nope`} {
		_, ok := parse([]byte(body))
		assert.False(t, ok, body)
	}
	r, ok := parse([]byte(`{"jsonrpc":null,"id":null,"method":"ping"}`))
	require.True(t, ok)
	assert.Nil(t, r.id, "a null id is a notification")
	r, ok = parse([]byte(`{"id": { "a" : 1 },"method":"ping","params":[1]}`))
	require.True(t, ok)
	assert.JSONEq(t, `{"a":1}`, string(r.id))
}

func TestToolResultRendersSortedJSONWithoutEscaping(t *testing.T) {
	result, err := toolResult(struct {
		Z   string  `json:"z"`
		A   float64 `json:"a"`
		URL string  `json:"url"`
	}{"<b>", 3, "https://x/y"})
	require.NoError(t, err)
	m := result.(map[string]any)
	text := m["content"].([]any)[0].(map[string]any)["text"]
	assert.Equal(t, `{"a":3,"url":"https://x/y","z":"<b>"}`, text)
	assert.Equal(t, false, m["isError"])
}
