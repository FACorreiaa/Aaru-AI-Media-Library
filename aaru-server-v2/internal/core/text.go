package core

import "github.com/rivo/uniseg"

// Length is a string's length as Swift's String.count measures it: in
// grapheme clusters, so a flag or a family emoji counts once. Every
// "at most N characters" rule ported from Swift counts with it.
func Length(s string) int {
	return uniseg.GraphemeClusterCount(s)
}

// Prefix is Swift's String.prefix(n): the first n grapheme clusters.
func Prefix(s string, n int) string {
	if n <= 0 {
		return ""
	}
	state, rest, count := -1, s, 0
	for rest != "" {
		_, rest, _, state = uniseg.FirstGraphemeClusterInString(rest, state)
		count++
		if count == n {
			return s[:len(s)-len(rest)]
		}
	}
	return s
}
