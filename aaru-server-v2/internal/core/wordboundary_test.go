package core

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestFindWordBoundedTreatsUnicodeLettersAsWordCharacters(t *testing.T) {
	episode := regexp.MustCompile(`[Ss](\d{1,3})\s*[Ee](\d{1,4})|(\d{1,3})x(\d{1,4})`)
	tests := []struct {
		in   string
		want string
	}{
		{"Show S01E02", "S01E02"},
		{"S01E02", "S01E02"},
		{"Show (2x03)", "2x03"},
		{"ShowS01E02", ""},
		{"éS01E02", ""},
		{"Café S01E02 é", "S01E02"},
		{"S01E02é", ""},
		{"éS01E02 then S03E04", "S03E04"},
		{"12x3456789", ""},
	}
	for _, tt := range tests {
		m := FindWordBounded(episode, tt.in)
		got := ""
		if m != nil {
			got = tt.in[m[0]:m[1]]
		}
		assert.Equal(t, tt.want, got, tt.in)
	}

	role := regexp.MustCompile(`(?i)(story|art)`)
	assert.True(t, MatchWordBounded(role, "Story & Art"))
	assert.True(t, MatchWordBounded(role, "Original Story"))
	assert.False(t, MatchWordBounded(role, "Artist"))
	assert.False(t, MatchWordBounded(role, "Storyboard"))
	assert.False(t, MatchWordBounded(role, "Kunstärt"))
}
