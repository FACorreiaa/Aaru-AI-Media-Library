package library

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Actor is who made a write. The ribbon shows it.
type Actor string

// The actors.
const (
	ActorUser          Actor = "user"
	ActorAgent         Actor = "agent"
	ActorExternalAgent Actor = "external_agent"
)

// Caller is who made a write and, for an outside caller, through which agent token (OUT-002).
// Its name prefixes the journal summary, so the ribbon says "Stremio: marked S1E2 … watched".
type Caller struct {
	Actor        Actor
	AgentTokenID *uuid.UUID
	AgentName    *string
	// Scrobbled: the write came from a player (Stremio or the browser extension); it earns the
	// scrobble bonus on top (GAM-001).
	Scrobbled bool
}

// UserCaller is the signed-in user's own tap.
var UserCaller = Caller{Actor: ActorUser}

// AgentCaller is an outside caller through an agent token.
func AgentCaller(token auth.AgentToken) Caller {
	group := token.Kind.Group()
	id, name := token.ID, token.Name
	return Caller{
		Actor: ActorExternalAgent, AgentTokenID: &id, AgentName: &name,
		Scrobbled: group == auth.GroupStremio || group == auth.GroupScrobble,
	}
}

// Summary prefixes text with the agent's name: "Stremio: marked …".
func (c Caller) Summary(text string) string {
	if c.AgentName == nil {
		return text
	}
	first, size := utf8.DecodeRuneInString(text)
	if size == 0 {
		return *c.AgentName + ": "
	}
	return *c.AgentName + ": " + strings.ToLower(string(first)) + text[size:]
}

// ActionRecord is one row of the action journal, as the ribbon reads it.
type ActionRecord struct {
	ID        uuid.UUID
	Actor     Actor
	Kind      string
	Summary   string
	ItemIDs   []uuid.UUID
	CreatedAt time.Time
	UndoneAt  *time.Time
	UndoOf    *uuid.UUID
	// AgentName is the agent token that made it, by its name at read time; nil for the user's own.
	AgentName *string
}

// ActionConflict is an action that cannot be undone (twice, or its target changed): 409.
type ActionConflict struct{ Message string }

func (e *ActionConflict) Error() string { return e.Message }

// AppError is the 409 `conflict` (apperr.Convertible).
func (e *ActionConflict) AppError() *apperr.Error { return apperr.Conflict(e.Message) }

// StoreConflict is a duplicate (user, title): 409.
type StoreConflict struct{ Message string }

func (e *StoreConflict) Error() string { return e.Message }

// AppError is the 409 `conflict` (apperr.Convertible).
func (e *StoreConflict) AppError() *apperr.Error { return apperr.Conflict(e.Message) }

// BookPosition is a book's reading position (both nil: none).
type BookPosition struct {
	Page    *int
	Percent *float64
}

// MangaPosition is a manga's last chapter and volume read (MNG-001).
type MangaPosition struct {
	Chapter *int
	Volume  *int
}

// ProgressSummary is a show's progress. PROG-003: counts exclude specials (season 0). Aired
// counts episodes whose air time has passed, plus undated episodes of an ended or canceled show.
type ProgressSummary struct {
	WatchedCount int
	AiredCount   int
	NextEpisode  *core.EpisodeKey
}

// Entry is a library item with the title it points at and derived progress (LibraryEntry).
type Entry struct {
	Item  core.LibraryItem
	Title core.Title
	// BookProgress is set for books only.
	BookProgress *BookPosition
	// Progress is set for shows only.
	Progress *ProgressSummary
	// MangaProgress is set for manga only.
	MangaProgress *MangaPosition
	// LastWatchedAt is the newest episode tick made live in Aaru; imported, pulled and restored
	// ticks do not count.
	LastWatchedAt *time.Time
	// StatusByHand: the status was chosen by a tap, not an import.
	StatusByHand bool
}

// InBacklog (APP-018) is an anime in progress the user never touched in Aaru: an imported status
// and no live tick. Derived, never stored, never a status.
func (e Entry) InBacklog() bool {
	return e.Title.IsAnime && e.Item.Status == core.StatusInProgress && !e.StatusByHand && e.LastWatchedAt == nil
}

// Fields are the entry's editable fields. StatusByHand stays nil, so a write built from them
// leaves the stored flag alone.
func (e Entry) Fields() ItemFields {
	f := ItemFields{
		Status: e.Item.Status, Notes: e.Item.Notes, IsOwned: e.Item.IsOwned, FinishedAt: e.Item.FinishedAt,
	}
	if e.Item.Rating != nil {
		v := e.Item.Rating.Value()
		f.Rating = &v
	}
	if e.BookProgress != nil {
		f.BookPage, f.BookPercent = e.BookProgress.Page, e.BookProgress.Percent
	}
	if e.MangaProgress != nil {
		f.MangaChapter, f.MangaVolume = e.MangaProgress.Chapter, e.MangaProgress.Volume
	}
	return f
}

// Filter is the grammar `GET /v1/library/items` accepts. Shelves store exactly this.
type Filter struct {
	Type    *core.MediaType     `json:"type,omitempty"`
	IsAnime *bool               `json:"isAnime,omitempty"`
	Status  *core.LibraryStatus `json:"status,omitempty"`
	IsOwned *bool               `json:"isOwned,omitempty"`
	ListID  *swiftUUID          `json:"listID,omitempty"`
}

// WithList is the filter narrowed to a list's members.
func (f Filter) WithList(id *uuid.UUID) Filter {
	if id == nil {
		f.ListID = nil
	} else {
		u := swiftUUID(*id)
		f.ListID = &u
	}
	return f
}

// List is the list the filter narrows to, if any.
func (f Filter) List() *uuid.UUID {
	if f.ListID == nil {
		return nil
	}
	id := uuid.UUID(*f.ListID)
	return &id
}

// Cursor is a keyset cursor over `(updated_at, id)` descending.
type Cursor struct {
	UpdatedAtMicros int64
	ID              uuid.UUID
}

// Token is the opaque wire form: base64 of "micros|UUID".
func (c Cursor) Token() string {
	return base64.StdEncoding.EncodeToString([]byte(fmt.Sprintf("%d|%s", c.UpdatedAtMicros, strings.ToUpper(c.ID.String()))))
}

// ParseCursor reads a token; false when it is not one.
func ParseCursor(token string) (Cursor, bool) {
	data, err := base64.StdEncoding.DecodeString(token)
	if err != nil || !utf8.Valid(data) {
		return Cursor{}, false
	}
	// Swift's split drops empty pieces.
	var parts []string
	for _, p := range strings.Split(string(data), "|") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) != 2 {
		return Cursor{}, false
	}
	micros, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return Cursor{}, false
	}
	id, ok := parseUUIDString(parts[1])
	if !ok {
		return Cursor{}, false
	}
	return Cursor{UpdatedAtMicros: micros, ID: id}, true
}

// parseUUIDString is Foundation's UUID(uuidString:): the 36-character hyphenated form only.
func parseUUIDString(s string) (uuid.UUID, bool) {
	if len(s) != 36 {
		return uuid.Nil, false
	}
	id, err := uuid.Parse(s)
	return id, err == nil
}

// StatusLabel is the status as people read it, per kind (APP-014). The stored value never
// changes: films and shows read Plan to watch / Watching / Watched; books and manga Plan to read
// / Reading / Read; albums Plan to listen / Listening / Listened (MUS-001). On hold reads the same
// for every kind (LIB-007).
func StatusLabel(status core.LibraryStatus, mediaType core.MediaType) string {
	planned, active, done := "Plan to watch", "Watching", "Watched"
	switch mediaType {
	case core.MediaBook, core.MediaManga:
		planned, active, done = "Plan to read", "Reading", "Read"
	case core.MediaAlbum:
		planned, active, done = "Plan to listen", "Listening", "Listened"
	}
	switch status {
	case core.StatusWishlist:
		return planned
	case core.StatusInProgress:
		return active
	case core.StatusOnHold:
		return "On hold"
	case core.StatusFinished:
		return done
	case core.StatusDropped:
		return "Dropped"
	}
	return string(status)
}

// HasAired: an episode with an air time has aired once it passed; an undated one has aired when
// the show ended or was canceled.
func HasAired(ep catalog.Episode, titleStatus *catalog.TitleStatus, now time.Time) bool {
	if ep.AirsAt != nil {
		return !ep.AirsAt.After(now)
	}
	return endedOrCanceled(titleStatus)
}

func endedOrCanceled(s *catalog.TitleStatus) bool {
	return s != nil && (*s == catalog.StatusEnded || *s == catalog.StatusCanceled)
}
