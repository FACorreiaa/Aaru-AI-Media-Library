package export

import (
	"aaru-go-api/internal/core"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestField(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"Arrival", "Arrival"},
		{"", ""},
		{"a,b", `"a,b"`},
		{`say "hi"`, `"say ""hi"""`},
		{"two\nlines", "\"two\nlines\""},
		{"=SUM(A1)", "'=SUM(A1)"},
		{"+1", "'+1"},
		{"-1", "'-1"},
		{"@me", "'@me"},
		{"=a,b", `"'=a,b"`},
	} {
		assert.Equal(t, tc.want, Field(tc.in), tc.in)
	}
}

func TestNumberAndStatusWord(t *testing.T) {
	assert.Equal(t, "8", Number(8))
	assert.Equal(t, "8.5", Number(8.5))
	assert.Equal(t, "Plan to watch", StatusWord(core.StatusWishlist))
	assert.Equal(t, "Watching", StatusWord(core.StatusInProgress))
	assert.Equal(t, "On hold", StatusWord(core.StatusOnHold))
	assert.Equal(t, "Completed", StatusWord(core.StatusFinished))
	assert.Equal(t, "Dropped", StatusWord(core.StatusDropped))
}
