package core

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLengthCountsGraphemes(t *testing.T) {
	tests := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"abc", 3},
		{"café", 4},
		{"é", 1},
		{"🇵🇹", 1},
		{"👨‍👩‍👧", 1},
		{"hi 👋🏽", 4},
	}
	for _, tt := range tests {
		assert.Equal(t, tt.want, Length(tt.in), tt.in)
	}
}

func TestPrefixKeepsWholeGraphemes(t *testing.T) {
	assert.Equal(t, "", Prefix("abc", 0))
	assert.Equal(t, "ab", Prefix("abc", 2))
	assert.Equal(t, "abc", Prefix("abc", 5))
	assert.Equal(t, "🇵🇹", Prefix("🇵🇹🇪🇸", 1))
	assert.Equal(t, "éx", Prefix("éxy", 2))
}
