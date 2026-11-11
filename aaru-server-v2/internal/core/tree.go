package core

import (
	"cmp"
	"slices"
)

// TreeBranchKind names a branch of a title tree (GRAPH-005): the series, the title's adaptations,
// or the person who made it.
type TreeBranchKind string

// The branch kinds.
const (
	BranchSeries     TreeBranchKind = "series"
	BranchAdaptation TreeBranchKind = "adaptation"
	BranchDirector   TreeBranchKind = "director"
	BranchCreator    TreeBranchKind = "creator"
	BranchStudio     TreeBranchKind = "studio"
	BranchAuthor     TreeBranchKind = "author"
	BranchArtist     TreeBranchKind = "artist"
	// A film's or show's first and second billed actor (GRAPH-006), sent only to a client that
	// asks for the cast.
	BranchLeadActor   TreeBranchKind = "lead_actor"
	BranchSecondActor TreeBranchKind = "second_actor"
)

// IsCast is true for a branch of someone who acted in the title rather than made it.
func (k TreeBranchKind) IsCast() bool { return k == BranchLeadActor || k == BranchSecondActor }

// TreePick says why a title is in a title tree.
type TreePick string

// The picks. Next is what the person made after the root; BestKnown is one of their works with
// the highest count at the provider, from any year.
const (
	PickRoot       TreePick = "root"
	PickNext       TreePick = "next"
	PickBestKnown  TreePick = "best_known"
	PickSeries     TreePick = "series"
	PickAdaptation TreePick = "adaptation"
)

// A branch holds TreeBranchSize titles; a person's branch opens with up to TreeNextCount of what
// they made next.
const (
	TreeBranchSize = 5
	TreeNextCount  = 3
)

// TreeCandidate is one of a person's works as the branch rule sees it. Date is `YYYY-MM-DD` or
// `YYYY`, "" when unknown. Score is the provider's count (votes, popularity, reading logs), the
// same for every user; 0 when the provider has none.
type TreeCandidate struct {
	Date  string
	Score int
}

// TreeChoice is one candidate picked for a branch, by its index.
type TreeChoice struct {
	Index int
	Pick  TreePick
}

// PickTreeBranch chooses a person's branch from their works, the root already left out: the next
// TreeNextCount works after rootDate, in date order, then the best known of the rest until the
// branch holds TreeBranchSize. Undated works are never picked. When ranked is false the provider
// has no count, and the branch is simply the next TreeBranchSize works by date.
func PickTreeBranch(works []TreeCandidate, rootDate string, ranked bool) []TreeChoice {
	dated := make([]int, 0, len(works))
	for i, w := range works {
		if w.Date != "" {
			dated = append(dated, i)
		}
	}
	slices.SortStableFunc(dated, func(a, b int) int { return cmp.Compare(works[a].Date, works[b].Date) })
	nextCount := TreeNextCount
	if !ranked {
		nextCount = TreeBranchSize
	}
	var out []TreeChoice
	picked := map[int]bool{}
	if rootDate != "" {
		for _, i := range dated {
			if len(out) == nextCount {
				break
			}
			if treeDateAfter(works[i].Date, rootDate) {
				out = append(out, TreeChoice{Index: i, Pick: PickNext})
				picked[i] = true
			}
		}
	}
	if !ranked {
		return out
	}
	rest := make([]int, 0, len(dated))
	for _, i := range dated {
		if !picked[i] && works[i].Score > 0 {
			rest = append(rest, i)
		}
	}
	slices.SortStableFunc(rest, func(a, b int) int { return cmp.Compare(works[b].Score, works[a].Score) })
	for _, i := range rest {
		if len(out) == TreeBranchSize {
			break
		}
		out = append(out, TreeChoice{Index: i, Pick: PickBestKnown})
	}
	return out
}

// treeDateAfter is true when date is later than root. A date known only by its year is compared
// by year, so a work of the root's own year is not "after" it.
func treeDateAfter(date, root string) bool {
	n := min(len(date), len(root))
	return date[:n] > root[:n]
}
