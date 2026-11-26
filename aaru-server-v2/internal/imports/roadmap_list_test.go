package imports

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestFreeListName(t *testing.T) {
	lists := func(names ...string) []core.AaruList {
		out := make([]core.AaruList, len(names))
		for i, n := range names {
			out[i] = core.AaruList{Name: n}
		}
		return out
	}
	long := strings.Repeat("a", capture.MaxListName)
	for _, tc := range []struct {
		name, want string
		existing   []core.AaruList
	}{
		{name: "Road to Dune", want: "Road to Dune", existing: lists("Favourites")},
		{name: "Road to Dune", want: "Road to Dune (2)", existing: lists("Road to Dune")},
		{name: "Road to Dune", want: "Road to Dune (2)", existing: lists("road to dune")},
		{name: "Road to Dune", want: "Road to Dune (3)", existing: lists("Road to Dune", "ROAD TO DUNE (2)")},
		{name: long, want: strings.Repeat("a", capture.MaxListName-4) + " (2)", existing: lists(long)},
	} {
		got := freeListName(tc.existing, tc.name)
		assert.Equal(t, tc.want, got, tc.name)
		assert.LessOrEqual(t, len([]rune(got)), capture.MaxListName)
	}
}
