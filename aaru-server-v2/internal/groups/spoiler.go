package groups

// SpoilerChoiceKind is how a message (or a Board post) is stamped.
type SpoilerChoiceKind int

// The choices: from the author's progress, not at all, or by hand.
const (
	SpoilerAuto SpoilerChoiceKind = iota
	SpoilerFree
	SpoilerStamped
)

// SpoilerChoice is a stamp choice; Stamp is set for SpoilerStamped.
type SpoilerChoice struct {
	Kind  SpoilerChoiceKind
	Stamp *SpoilerStamp
}

var errBadStamp = Invalid("spoiler", "Stamp a season and episode, or the ending.")

// ParseSpoilerChoice reads the request's stamp (present: the body has a `spoiler` object):
// absent means from the author's progress, `spoilerFree` means none, and a stamp needs a whole
// episode or the ending.
func ParseSpoilerChoice(present bool, season, episode *int, ending, free *bool) (SpoilerChoice, error) {
	switch {
	case free != nil && *free:
		return SpoilerChoice{Kind: SpoilerFree}, nil
	case !present:
		return SpoilerChoice{Kind: SpoilerAuto}, nil
	case ending != nil && *ending:
		return SpoilerChoice{Kind: SpoilerStamped, Stamp: EndingStamp()}, nil
	case season != nil && episode != nil && *season >= 0 && *episode >= 1:
		return SpoilerChoice{Kind: SpoilerStamped, Stamp: EpisodeStamp(EpisodePoint{Season: *season, Episode: *episode})}, nil
	default:
		return SpoilerChoice{}, errBadStamp
	}
}
