package capture_test

import (
	"aaru-go-api/internal/capture"
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-003: a roadmap's steps, notes, optional titles and pairs, read loosely from the model.

func TestRowsReadARoadmap(t *testing.T) {
	input := json.RawMessage(`{"list_name":"Secret Wars","steps":[
		{"heading":"  Hickman FF  ","note":"The Reed arc"},{"note":"no heading"},{"heading":"Avengers"}],
	 "titles":[
		{"title":"FF Vol 1","type":"book","step":1,"note":"FF #570-575","pair":2},
		{"title":"Avengers Vol 1","type":"book","step":2,"optional":true},
		{"title":"Out of range","type":"book","step":9,"note":"` + strings.Repeat("x", 300) + `"},
		{"title":"Plain","type":"book"}]}`)
	rows := capture.Rows(input)
	require.Len(t, rows, 4)

	require.NotNil(t, rows[0].Place)
	assert.Equal(t, capture.Place{Step: 1, Heading: "Hickman FF", StepNote: "The Reed arc", Note: "FF #570-575", Pair: 2}, *rows[0].Place)
	// The step with no heading is dropped, so "Avengers" is step 2.
	assert.Equal(t, capture.Place{Step: 2, Heading: "Avengers", Optional: true}, *rows[1].Place)
	assert.Zero(t, rows[2].Place.Step, "a step that does not exist keeps the note, not the step")
	assert.Len(t, []rune(rows[2].Place.Note), capture.MaxNote)
	assert.Nil(t, rows[3].Place, "a plain title has no place")
}
