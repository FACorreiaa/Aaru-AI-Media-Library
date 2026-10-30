package core

import (
	"fmt"
	"strconv"
	"strings"
	"unicode"

	"golang.org/x/text/cases"
	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
	"golang.org/x/text/width"
)

// MatchKey is the fallback identity for a title: normalized name + year + type.
//
// Only used after external ids fail to match. Two titles that share nothing but a
// similar name must never be merged, which is why year and type are part of the
// key and why an absent year makes the key weaker, not broader.
type MatchKey struct {
	NormalizedTitle string
	Year            *int
	Type            MediaType
}

// NewMatchKey normalizes title.
func NewMatchKey(title string, year *int, mediaType MediaType) MatchKey {
	return MatchKey{NormalizedTitle: NormalizeTitle(title), Year: year, Type: mediaType}
}

func (k MatchKey) String() string {
	year := "-"
	if k.Year != nil {
		year = strconv.Itoa(*k.Year)
	}
	return fmt.Sprintf("%s:%s:%s", k.Type, k.NormalizedTitle, year)
}

// fold is Foundation's diacritic-, case- and width-insensitive folding.
func fold(s string) string {
	t := transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC, width.Fold)
	out, _, err := transform.String(t, s)
	if err != nil {
		out = s
	}
	return cases.Fold().String(out)
}

func isAlphanumeric(r rune) bool {
	return unicode.IsLetter(r) || unicode.IsMark(r) || unicode.IsNumber(r)
}

// NormalizeTitle folds a display title down to something two providers can agree on.
//
// Lowercases, strips diacritics, drops a leading article, removes punctuation,
// and collapses whitespace. Deliberately conservative: it must not make two
// different works collide.
func NormalizeTitle(title string) string {
	unpunctuated := strings.Map(func(r rune) rune {
		if isAlphanumeric(r) {
			return r
		}
		return ' '
	}, fold(title))
	return dropLeadingArticle(strings.Join(strings.Fields(unpunctuated), " "))
}

var leadingArticles = []string{"the ", "a ", "an "}

func dropLeadingArticle(title string) string {
	for _, article := range leadingArticles {
		if strings.HasPrefix(title, article) {
			stripped := title[len(article):]
			// "The The" or a title that is only an article keeps its original form.
			if stripped == "" {
				return title
			}
			return stripped
		}
	}
	return title
}

// CanMerge is whether two refs may describe the same work.
//
// External ids decide when either side has one in common. Name matching is the
// fallback and requires the same type; a missing year on one side is allowed,
// two different years are not.
func CanMerge(lhs, rhs MediaRef) bool {
	// A movie and a show are never the same work — and TMDB/Trakt number them
	// separately, so a shared id across types is a coincidence, not a match.
	if lhs.Type != rhs.Type {
		return false
	}
	if lhs.IDs.Matches(rhs.IDs) {
		return true
	}
	left, ok1 := lhs.MatchKey()
	right, ok2 := rhs.MatchKey()
	if !ok1 || !ok2 || left.NormalizedTitle != right.NormalizedTitle || left.NormalizedTitle == "" {
		return false
	}
	if left.Year == nil || right.Year == nil {
		return true
	}
	return *left.Year == *right.Year
}

// CanMergeBook is IMP-020: whether a book one year off may still be the same work.
// Goodreads and Open Library often disagree on a first year by one, so a book may
// match one year off, but only when its author is also one of the hit's authors.
// Both years must be known. The caller still takes it only when exactly one hit
// qualifies. Books only: no other kind is loosened.
func CanMergeBook(lhs MediaRef, author *string, rhs MediaRef, byline *string) bool {
	if lhs.Type != MediaBook || rhs.Type != MediaBook || author == nil || byline == nil || !SameAuthor(*author, *byline) {
		return false
	}
	left, ok1 := lhs.MatchKey()
	right, ok2 := rhs.MatchKey()
	if !ok1 || !ok2 || left.NormalizedTitle == "" || left.NormalizedTitle != right.NormalizedTitle ||
		left.Year == nil || right.Year == nil {
		return false
	}
	d := *left.Year - *right.Year
	return d >= -1 && d <= 1
}

// SameAuthor is whether author is one of the names in byline (comma separated, as
// a catalog lists them). Case, accents, punctuation and spacing are ignored, so
// "James S.A. Corey" is "James S. A. Corey"; anything else must be the same letters.
func SameAuthor(author, byline string) bool {
	wanted := authorKey(author)
	if wanted == "" {
		return false
	}
	for name := range strings.SplitSeq(byline, ",") {
		if name != "" && authorKey(name) == wanted {
			return true
		}
	}
	return false
}

func authorKey(name string) string {
	return strings.Map(func(r rune) rune {
		if isAlphanumeric(r) {
			return r
		}
		return -1
	}, fold(name))
}
