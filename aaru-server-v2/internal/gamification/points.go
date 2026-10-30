// Package gamification is the points ledger, levels, streaks, badges and the friends board
// (GAM-001…005), ported from aaru-server's Sources/App/Gamification.
//
// Every award goes through the store's idempotent ledger (X-010): a row per award, keyed by a
// dedupe root, never a counter. Library writes record their points inside the library's own
// transaction through RecordLibraryWrite; everything else goes through Service.
package gamification

import (
	"aaru-go-api/internal/core"
	"fmt"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Kind is what earns points (PointsKind). Values live here, not in the database, so tuning
// them is a code change with a test.
type Kind string

const (
	KindEpisode         Kind = "episode"
	KindMovieFinished   Kind = "movie_finished"
	KindBookFinished    Kind = "book_finished"
	KindAlbumFinished   Kind = "album_finished"
	KindSeasonBonus     Kind = "season_bonus"
	KindScrobbleBonus   Kind = "scrobble_bonus"
	KindBookProgress    Kind = "book_progress"
	KindListen          Kind = "listen"
	KindRoomAttended    Kind = "room_attended"
	KindFriendAdded     Kind = "friend_added"
	KindImportFirst     Kind = "import_first"
	KindStreakMilestone Kind = "streak_milestone"
)

// AllKinds in declaration order (CaseIterable).
var AllKinds = []Kind{
	KindEpisode, KindMovieFinished, KindBookFinished, KindAlbumFinished, KindSeasonBonus, KindScrobbleBonus,
	KindBookProgress, KindListen, KindRoomAttended, KindFriendAdded, KindImportFirst, KindStreakMilestone,
}

// Points is the award for one event of the kind.
func (k Kind) Points() int {
	switch k {
	case KindEpisode:
		return 10
	case KindMovieFinished:
		return 25
	case KindBookFinished:
		return 50
	case KindAlbumFinished:
		return 10
	case KindSeasonBonus:
		return 30
	case KindScrobbleBonus:
		return 5
	case KindBookProgress:
		return 5
	case KindListen:
		return 1
	case KindRoomAttended:
		return 15
	case KindFriendAdded:
		return 20
	case KindImportFirst:
		return 50
	}
	return 0
}

// DailyCap is the most one kind earns in a local day; false for no cap (one-off kinds and
// streak milestones).
func (k Kind) DailyCap() (int, bool) {
	switch k {
	case KindEpisode:
		return 300, true
	case KindMovieFinished:
		return 100, true
	case KindBookFinished:
		return 150, true
	case KindAlbumFinished:
		return 50, true
	case KindSeasonBonus:
		return 90, true
	case KindScrobbleBonus:
		return 50, true
	case KindBookProgress:
		return 15, true
	case KindListen:
		return 25, true
	case KindRoomAttended:
		return 45, true
	case KindFriendAdded:
		return 60, true
	}
	return 0, false
}

// OnBoard is whether the kind counts on the weekly friends board. Making friends and moving in
// are not a week's watching (owner decision 2026-10-22).
func (k Kind) OnBoard() bool {
	return k != KindFriendAdded && k != KindImportFirst
}

// OncePerRoot kinds have their root spent by the first award, even once revoked: re-friending,
// a second first import, rejoining a party or a rebuilt streak earn nothing again.
func (k Kind) OncePerRoot() bool {
	switch k {
	case KindFriendAdded, KindImportFirst, KindRoomAttended, KindStreakMilestone:
		return true
	}
	return false
}

// MarksStreakDay kinds make a day a streak day.
func (k Kind) MarksStreakDay() bool {
	switch k {
	case KindEpisode, KindMovieFinished, KindBookFinished, KindAlbumFinished, KindBookProgress:
		return true
	}
	return false
}

// StreakBonus is the bonus for reaching a milestone run length.
func StreakBonus(days int) int {
	switch days {
	case 7:
		return 50
	case 30:
		return 200
	case 100:
		return 500
	case 365:
		return 1000
	}
	return 0
}

// OffBoardKinds are the kinds the board leaves out.
func OffBoardKinds() []string {
	var kinds []string
	for _, k := range AllKinds {
		if !k.OnBoard() {
			kinds = append(kinds, string(k))
		}
	}
	return kinds
}

func streakKinds() []string {
	var kinds []string
	for _, k := range AllKinds {
		if k.MarksStreakDay() {
			kinds = append(kinds, string(k))
		}
	}
	return kinds
}

// Award is one award to make: the root ties it to its later revocation (PointsAward).
type Award struct {
	Kind     Kind
	Root     string
	Points   int
	TitleID  *uuid.UUID
	ActionID *uuid.UUID
}

// NewAward is an award at the kind's own points.
func NewAward(kind Kind, root string, titleID, actionID *uuid.UUID) Award {
	return Award{Kind: kind, Root: root, Points: kind.Points(), TitleID: titleID, ActionID: actionID}
}

// upper is Swift's uuidString: the roots stored in the ledger carry uppercase ids.
func upper(id uuid.UUID) string {
	return strings.ToUpper(id.String())
}

// Dedupe roots (PointsRoot). Keyed by title, not library item, so removing a title and adding it
// back earns nothing twice.

// EpisodeRoot is one episode of a title.
func EpisodeRoot(title uuid.UUID, key core.EpisodeKey) string {
	return fmt.Sprintf("ep:%s:%d:%d", upper(title), key.Season, key.Episode)
}

// ScrobbleRoot is the scrobble bonus for one episode.
func ScrobbleRoot(title uuid.UUID, key core.EpisodeKey) string {
	return fmt.Sprintf("scrobble:%s:%d:%d", upper(title), key.Season, key.Episode)
}

// ScrobbleFinishRoot is the scrobble bonus for a finish.
func ScrobbleFinishRoot(title uuid.UUID) string {
	return "scrobble:" + upper(title)
}

// SeasonRoot is a season bonus.
func SeasonRoot(title uuid.UUID, season int) string {
	return fmt.Sprintf("season:%s:%d", upper(title), season)
}

// FinishRoot is a finish.
func FinishRoot(title uuid.UUID) string {
	return "finish:" + upper(title)
}

// BookDayRoot is one day's book progress on one title.
func BookDayRoot(title uuid.UUID, date string) string {
	return fmt.Sprintf("book:%s:%s", upper(title), date)
}

// FriendRoot is one friendship, the same for both sides.
func FriendRoot(first, second uuid.UUID) string {
	pair := []string{upper(first), upper(second)}
	slices.Sort(pair)
	return fmt.Sprintf("friend:%s:%s", pair[0], pair[1])
}

// RoomRoot is one watch party.
func RoomRoot(session uuid.UUID) string {
	return "room:" + upper(session)
}

// Listen is what the ledger needs of one kept listen (NewListen).
type Listen struct {
	ListenedAt time.Time
	Artist     string
	Track      string
}

// ListenRoot is one play of one track at one moment, as the listens table keys it.
func ListenRoot(listen Listen) string {
	return fmt.Sprintf("listen:%d:%s:%s", listen.ListenedAt.Unix(), strings.ToLower(listen.Artist),
		strings.ToLower(listen.Track))
}

// ImportFirstRoot is the first import.
const ImportFirstRoot = "import:first"

// StreakRoot is one milestone of one run.
func StreakRoot(runStart string, days int) string {
	return fmt.Sprintf("streak:%s:%d", runStart, days)
}

// LevelThreshold is the points to reach level L: `50·L·(L−1)` (GAM-002).
func LevelThreshold(level int) int {
	return 50 * level * (level - 1)
}

// LevelFor is the level a total reaches; level 1 at 0 points. Never stored.
func LevelFor(total int) int {
	if total <= 0 {
		return 1
	}
	level := int(math.Floor((1 + math.Sqrt(1+4*float64(total)/50)) / 2))
	// Guard against floating point at exact boundaries.
	for LevelThreshold(level+1) <= total {
		level++
	}
	for level > 1 && LevelThreshold(level) > total {
		level--
	}
	return max(1, level)
}

// finishKind is the kind a finish earns; false for shows.
func finishKind(t core.MediaType) (Kind, bool) {
	switch t {
	case core.MediaMovie:
		return KindMovieFinished, true
	// Manga is reading: it earns as a book does (MNG-001).
	case core.MediaBook, core.MediaManga:
		return KindBookFinished, true
	case core.MediaAlbum:
		return KindAlbumFinished, true
	}
	return "", false
}
