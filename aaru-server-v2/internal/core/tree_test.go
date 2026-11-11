package core

import (
	"reflect"
	"testing"
)

func TestPickTreeBranch(t *testing.T) {
	works := []TreeCandidate{
		{Date: "2013-09-20", Score: 900},  // 0 before the root, well known
		{Date: "2017-10-06", Score: 800},  // 1 next
		{Date: "2021-10-22", Score: 1000}, // 2 next
		{Date: "2024-03-01", Score: 700},  // 3 next
		{Date: "2026-12-18", Score: 10},   // 4 after, past the three
		{Date: "2015-10-02", Score: 850},  // 5 before the root
		{Date: "", Score: 5000},           // 6 undated: never picked
		{Date: "2010-01-01", Score: 0},    // 7 no count: never best known
	}
	got := PickTreeBranch(works, "2016-11-11", true)
	want := []TreeChoice{
		{1, PickNext}, {2, PickNext}, {3, PickNext}, {0, PickBestKnown}, {5, PickBestKnown},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestPickTreeBranchFillsWithBestKnownWhenLittleCameNext(t *testing.T) {
	works := []TreeCandidate{
		{Date: "1965", Score: 10},
		{Date: "1969", Score: 30},
		{Date: "1976", Score: 20},
		{Date: "1984", Score: 5},
		{Date: "1985", Score: 40},
		{Date: "1986", Score: 1},
	}
	got := PickTreeBranch(works, "1985", true)
	// Index 4 shares the root's year: not next, but still one of the best known.
	want := []TreeChoice{{5, PickNext}, {4, PickBestKnown}, {1, PickBestKnown}, {2, PickBestKnown}, {0, PickBestKnown}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestPickTreeBranchYearOnlyRoot(t *testing.T) {
	works := []TreeCandidate{{Date: "2016-12-01", Score: 1}, {Date: "2017-01-01", Score: 1}}
	got := PickTreeBranch(works, "2016", true)
	if len(got) != 2 || got[0] != (TreeChoice{1, PickNext}) || got[1] != (TreeChoice{0, PickBestKnown}) {
		t.Fatalf("a work of the root's own year is not next: %v", got)
	}
}

func TestPickTreeBranchUnranked(t *testing.T) {
	works := []TreeCandidate{
		{Date: "1993-02-22"},
		{Date: "1997-05-21"},
		{Date: "2000-08-03"},
		{Date: "2001-05-30"},
		{Date: "2003-05-26"},
		{Date: "2007-10-10"},
		{Date: "2011-02-18"},
	}
	got := PickTreeBranch(works, "1997-05-21", false)
	want := []TreeChoice{{2, PickNext}, {3, PickNext}, {4, PickNext}, {5, PickNext}, {6, PickNext}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	if got := PickTreeBranch(works, "", false); len(got) != 0 {
		t.Fatalf("no root date and no count leaves nothing to pick: %v", got)
	}
}

func TestPickTreeBranchNoRootDateIsAllBestKnown(t *testing.T) {
	works := []TreeCandidate{{Date: "2001", Score: 3}, {Date: "2002", Score: 9}}
	got := PickTreeBranch(works, "", true)
	want := []TreeChoice{{1, PickBestKnown}, {0, PickBestKnown}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
