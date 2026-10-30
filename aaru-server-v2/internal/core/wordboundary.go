package core

import (
	"regexp"
	"unicode"
	"unicode/utf8"
)

// FindWordBounded is Swift's (ICU's) `\b…\b` around re: the first match of re whose ends are word
// boundaries, as submatch indexes; nil when there is none. RE2's `\b` knows only ASCII letters, so
// "éS01E02" would match there and not in Swift. re must not use `\b` itself; every match of it must
// start and end on a word character.
func FindWordBounded(re *regexp.Regexp, s string) []int {
	for from := 0; from <= len(s); {
		m := re.FindStringSubmatchIndex(s[from:])
		if m == nil {
			return nil
		}
		for i := range m {
			if m[i] >= 0 {
				m[i] += from
			}
		}
		if boundaryBefore(s, m[0]) && boundaryAfter(s, m[1]) {
			return m
		}
		// Try again one character past this match's start, as the regex engine would.
		_, size := utf8.DecodeRuneInString(s[m[0]:])
		from = m[0] + max(size, 1)
	}
	return nil
}

// MatchWordBounded is FindWordBounded's yes or no.
func MatchWordBounded(re *regexp.Regexp, s string) bool { return FindWordBounded(re, s) != nil }

func boundaryBefore(s string, i int) bool {
	if i == 0 {
		return true
	}
	r, _ := utf8.DecodeLastRuneInString(s[:i])
	return !isWordRune(r)
}

func boundaryAfter(s string, i int) bool {
	if i >= len(s) {
		return true
	}
	r, _ := utf8.DecodeRuneInString(s[i:])
	return !isWordRune(r)
}

// isWordRune is ICU's \w: letters, marks, decimal digits, connector punctuation, ZWNJ and ZWJ.
func isWordRune(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsMark(r) || unicode.IsDigit(r) || unicode.Is(unicode.Nl, r) ||
		unicode.Is(unicode.Pc, r) || r == '‌' || r == '‍'
}
