package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"slices"
	"strings"
)

// Guess is the catalog's best hit for a row the strict match refused (IMP-021). The strict match
// never merges two titles that only share a similar name, and it stays that way: a guess is only
// ever a proposal the person sees, with what it found, before they approve.
type Guess struct {
	Title     core.Title
	Byline    *string
	PosterURL *string
}

// The least of a row's title a book must share to be guessed at all.
const guessMinOverlap = 0.5

// Guess finds a best guess for a name, or nil when nothing is close enough.
func (r Resolver) Guess(ctx context.Context, mediaType core.MediaType, name string, author *string, year *int) (*Guess, error) {
	var hit *Hit
	var err error
	switch mediaType {
	case core.MediaBook:
		hit, err = r.guessBook(ctx, name, author)
	case core.MediaMovie, core.MediaShow:
		hit, err = guessByName(ctx, r.Providers.TMDB, mediaType, name, year)
	case core.MediaManga:
		hit, err = guessByName(ctx, r.Providers.AniList, mediaType, name, year)
	default:
		return nil, nil // nil: no guess for this kind
	}
	if err != nil || hit == nil {
		return nil, err
	}
	title, err := r.resolveIDs(ctx, hit.IDs, mediaType)
	if err != nil {
		return nil, fmt.Errorf("resolve guess: %w", err)
	}
	return &Guess{Title: title, Byline: hit.Byline, PosterURL: hit.PosterURL}, nil
}

// guessBook searches the whole name, then the part a catalog is likelier to file it under with the
// author: Open Library has "X-Men: Days of Future Past" as "Days of Future Past". A row with an
// author takes the best hit by them; a row without one takes an exact title only.
func (r Resolver) guessBook(ctx context.Context, name string, author *string) (*Hit, error) {
	hits, err := r.Providers.OpenLibrary.Search(ctx, name, core.MediaBook)
	if err != nil {
		return nil, fmt.Errorf("search %q: %w", name, err)
	}
	if author == nil || strings.TrimSpace(*author) == "" {
		wanted := core.NormalizeTitle(name)
		for i, h := range hits {
			if core.NormalizeTitle(h.Title) == wanted || core.NormalizeTitle(fullTitle(h)) == wanted {
				return &hits[i], nil
			}
		}
		return nil, nil // nil: an inexact title with no author to back it is no guess
	}
	short := name
	if _, subtitle, ok := strings.Cut(name, ":"); ok && strings.TrimSpace(subtitle) != "" {
		short = strings.TrimSpace(subtitle)
	}
	more, err := r.Providers.OpenLibrary.Search(ctx, short+" "+*author, core.MediaBook)
	if err != nil {
		return nil, fmt.Errorf("search %q: %w", short, err)
	}
	var best *Hit
	var bestScore float64
	all := slices.Concat(hits, more)
	for i, h := range all {
		if score := bookGuessScore(name, *author, h); score > bestScore {
			best, bestScore = &all[i], score
		}
	}
	return best, nil
}

// bookGuessScore is how well a hit fits, or 0 when it must not be guessed: by someone else, or
// sharing too little of the title.
func bookGuessScore(name, author string, h Hit) float64 {
	weight := authorWeight(author, h.Byline)
	if weight == 0 {
		return 0
	}
	wanted, found := titleWords(name), titleWords(fullTitle(h))
	if len(wanted) == 0 || len(found) == 0 {
		return 0
	}
	shared := 0
	for word := range wanted {
		if found[word] {
			shared++
		}
	}
	overlap := float64(shared) / float64(len(wanted))
	if overlap < guessMinOverlap {
		return 0
	}
	extra := float64(len(found)-shared) / float64(len(found))
	score := overlap*2 - extra/2 + weight
	if h.PosterURL != nil {
		score += 0.2
	}
	return score
}

// authorWeight is 1.5 for the same name, 1 for the same words in another order or the same last
// name ("Cixin Liu", "Andy Hunt" for "Andrew Hunt"), 0 for anyone else.
func authorWeight(author string, byline *string) float64 {
	if byline == nil {
		return 0
	}
	if core.SameAuthor(author, *byline) {
		return 1.5
	}
	wanted := titleWords(author)
	last := lastWord(author)
	for name := range strings.SplitSeq(*byline, ",") {
		if last != "" && lastWord(name) == last || sameWords(wanted, titleWords(name)) {
			return 1
		}
	}
	return 0
}

func lastWord(name string) string {
	words := strings.Fields(core.NormalizeTitle(name))
	if len(words) == 0 {
		return ""
	}
	return words[len(words)-1]
}

func sameWords(a, b map[string]bool) bool {
	if len(a) == 0 || len(a) != len(b) {
		return false
	}
	for word := range a {
		if !b[word] {
			return false
		}
	}
	return true
}

func titleWords(title string) map[string]bool {
	words := map[string]bool{}
	for _, word := range strings.Fields(core.NormalizeTitle(title)) {
		words[word] = true
	}
	return words
}

// fullTitle is a hit's title with its subtitle.
func fullTitle(h Hit) string {
	if h.Subtitle == nil {
		return h.Title
	}
	return h.Title + ": " + *h.Subtitle
}

// guessByName takes the hit with this exact name, in this year when one has it. Film, show and
// manga rows carry no author to back anything looser.
func guessByName(ctx context.Context, searcher Searcher, mediaType core.MediaType, name string, year *int) (*Hit, error) {
	if searcher == nil {
		return nil, nil // nil: this catalog is off
	}
	hits, err := searcher.Search(ctx, name, mediaType)
	if err != nil {
		return nil, fmt.Errorf("search %q: %w", name, err)
	}
	wanted := core.NormalizeTitle(name)
	var best *Hit
	for i, h := range hits {
		if core.NormalizeTitle(h.Title) != wanted {
			continue
		}
		if year != nil && h.Year != nil && *h.Year == *year {
			return &hits[i], nil
		}
		if best == nil {
			best = &hits[i]
		}
	}
	return best, nil
}
