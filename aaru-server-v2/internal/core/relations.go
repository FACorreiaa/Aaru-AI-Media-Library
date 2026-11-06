package core

// Relation is how one title stands to another in the catalog (GRAPH-001): read as "B is A's
// <relation>". Catalog data, never a library write, never a recommendation. Raw values are a wire
// contract; AaruCore's Relation holds the same set with the same meaning.
type Relation string

// The relations.
const (
	RelationPrequel     Relation = "prequel"
	RelationSequel      Relation = "sequel"
	RelationSideStory   Relation = "side_story"
	RelationSpinOff     Relation = "spin_off"
	RelationAdaptation  Relation = "adaptation"
	RelationSource      Relation = "source"
	RelationAlternative Relation = "alternative"
	RelationSummary     Relation = "summary"
	RelationParent      Relation = "parent"
	RelationOther       Relation = "other"
)

// Relations are every relation, in declaration order.
var Relations = []Relation{
	RelationPrequel, RelationSequel, RelationSideStory, RelationSpinOff, RelationAdaptation,
	RelationSource, RelationAlternative, RelationSummary, RelationParent, RelationOther,
}

// Valid reports whether r is a known relation.
func (r Relation) Valid() bool {
	for _, known := range Relations {
		if r == known {
			return true
		}
	}
	return false
}

// MainChain is true for prequel and sequel: the line a graph draws first and "Start here" walks.
func (r Relation) MainChain() bool { return r == RelationPrequel || r == RelationSequel }

// Canonical is the same fact written forward, so each pair is stored once: "A's prequel is B" is
// "B's sequel is A", "A's source is B" is "B's adaptation is A", and "A's parent is B" is "B's side
// story is A". flipped is true when the two ends swap.
func (r Relation) Canonical() (canonical Relation, flipped bool) {
	switch r {
	case RelationPrequel:
		return RelationSequel, true
	case RelationSource:
		return RelationAdaptation, true
	case RelationParent:
		return RelationSideStory, true
	}
	return r, false
}

// SameMedium is true when a sequel between these kinds stays on the main chain: films and shows
// are one medium (an anime film continues a series), every other kind is its own.
func SameMedium(a, b MediaType) bool {
	screen := func(t MediaType) bool { return t == MediaMovie || t == MediaShow }
	return a == b || (screen(a) && screen(b))
}
