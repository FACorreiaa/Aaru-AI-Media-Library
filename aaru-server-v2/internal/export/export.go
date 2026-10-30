// Package export is `GET /v1/me/export` (AccountExport.swift): everything Aaru holds for one
// user, as JSON or as a CSV Aaru's own generic importer reads back. Reads only.
//
// The library, lists, shelves, social, groups, listens and favorites are each another area's
// data; until those areas are ported, the export reads their tables itself
// (internal/db/queries/export.sql, internal/schedule's entry reads). Fold after merge.
package export

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/schedule"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"
)

// syncLimit is the library sync's "every item" bound (PostgresLibraryStore.changes).
const syncLimit = 100_000

// List is one user list with its titles, in list order.
type List struct {
	Name      string
	CreatedAt time.Time
	Titles    []core.Title
}

// ShelfFilter is a shelf's saved filter as stored (Swift's LibraryFilter, Codable keys).
type ShelfFilter struct {
	Type    *core.MediaType     `json:"type,omitempty"`
	IsAnime *bool               `json:"isAnime,omitempty"`
	Status  *core.LibraryStatus `json:"status,omitempty"`
	IsOwned *bool               `json:"isOwned,omitempty"`
	ListID  *uuid.UUID          `json:"listID,omitempty"`
}

// Shelf is one saved query.
type Shelf struct {
	ID       uuid.UUID
	Name     string
	Filter   ShelfFilter
	IsPinned bool
}

// Account is the library part of the export: every item (oldest added first), watched episodes
// per show (only shows with any), lists with their titles, and shelves.
type Account struct {
	Entries []schedule.LibraryEntry
	Watched map[uuid.UUID][]core.EpisodeKey
	Lists   []List
	Shelves []Shelf
}

// Service gathers an export.
type Service struct {
	Pool *pgxpool.Pool
	Q    *sqlc.Queries
	Now  func() time.Time
}

// New is the service over a pool.
func New(pool *pgxpool.Pool) *Service {
	return &Service{Pool: pool, Q: sqlc.New(pool)}
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// Gather reads the library, lists and shelves. Ticks and list titles are one query each, not one
// per show or per list.
func (s *Service) Gather(ctx context.Context, userID uuid.UUID) (Account, error) {
	var (
		out   Account
		lists []List
	)
	g, gctx := errgroup.WithContext(ctx)
	g.Go(func() error {
		entries, err := schedule.ReadEntries(gctx, s.Pool, userID, schedule.EntryFilter{}, syncLimit, s.now())
		if err != nil {
			return err
		}
		slices.SortStableFunc(entries, func(a, b schedule.LibraryEntry) int {
			return a.Item.AddedAt.Compare(b.Item.AddedAt)
		})
		var shows []uuid.UUID
		for _, e := range entries {
			if e.Title.Type == core.MediaShow {
				shows = append(shows, e.Item.ID)
			}
		}
		watched, err := schedule.ReadWatched(gctx, s.Pool, shows)
		if err != nil {
			return err
		}
		out.Entries, out.Watched = entries, watched
		return nil
	})
	g.Go(func() error {
		var err error
		lists, err = s.lists(gctx, userID)
		return err
	})
	g.Go(func() error {
		var err error
		out.Shelves, err = s.shelves(gctx, userID)
		return err
	})
	if err := g.Wait(); err != nil {
		return Account{}, err
	}
	out.Lists = lists
	return out, nil
}

func (s *Service) lists(ctx context.Context, userID uuid.UUID) ([]List, error) {
	rows, err := s.Q.ExportLists(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("export lists: %w", err)
	}
	if len(rows) == 0 {
		return []List{}, nil
	}
	ids := make([]uuid.UUID, 0, len(rows))
	for _, r := range rows {
		ids = append(ids, r.ID)
	}
	members, err := s.Q.ExportListItems(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("export list items: %w", err)
	}
	byList := map[uuid.UUID][]uuid.UUID{}
	seen := map[uuid.UUID]bool{}
	var unique []uuid.UUID
	for _, m := range members {
		byList[m.ListID] = append(byList[m.ListID], m.TitleID)
		if !seen[m.TitleID] {
			seen[m.TitleID] = true
			unique = append(unique, m.TitleID)
		}
	}
	titles, err := s.titles(ctx, unique)
	if err != nil {
		return nil, err
	}
	out := make([]List, 0, len(rows))
	for _, r := range rows {
		list := List{Name: r.Name, CreatedAt: r.CreatedAt, Titles: []core.Title{}}
		for _, id := range byList[r.ID] {
			if t, ok := titles[id]; ok {
				list.Titles = append(list.Titles, t)
			}
		}
		out = append(out, list)
	}
	return out, nil
}

func (s *Service) titles(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]core.Title, error) {
	out := map[uuid.UUID]core.Title{}
	if len(ids) == 0 {
		return out, nil
	}
	titles, err := catalog.NewStore(s.Pool).Titles(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("export titles: %w", err)
	}
	for _, t := range titles {
		if _, ok := out[t.ID]; !ok {
			out[t.ID] = t
		}
	}
	return out, nil
}

func (s *Service) shelves(ctx context.Context, userID uuid.UUID) ([]Shelf, error) {
	rows, err := s.Q.ExportShelves(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("export shelves: %w", err)
	}
	out := make([]Shelf, 0, len(rows))
	for _, r := range rows {
		var raw struct {
			Type    *string    `json:"type"`
			IsAnime *bool      `json:"isAnime"`
			Status  *string    `json:"status"`
			IsOwned *bool      `json:"isOwned"`
			ListID  *uuid.UUID `json:"listID"`
		}
		if err := json.Unmarshal(r.Filter, &raw); err != nil {
			return nil, fmt.Errorf("export shelf filter: %w", err)
		}
		f := ShelfFilter{IsAnime: raw.IsAnime, IsOwned: raw.IsOwned, ListID: raw.ListID}
		if raw.Type != nil {
			t := core.MediaType(*raw.Type)
			if !t.Valid() {
				return nil, fmt.Errorf("export shelf filter: unknown type %q", *raw.Type)
			}
			f.Type = &t
		}
		if raw.Status != nil {
			st := core.LibraryStatus(*raw.Status)
			if !st.Valid() {
				return nil, fmt.Errorf("export shelf filter: unknown status %q", *raw.Status)
			}
			f.Status = &st
		}
		out = append(out, Shelf{ID: r.ID, Name: r.Name, Filter: f, IsPinned: r.IsPinned})
	}
	return out, nil
}

// Favorites is the user's top 10s by kind (film, show, anime, manga, book, album), in order.
func (s *Service) Favorites(ctx context.Context, userID uuid.UUID) (map[string][]core.Title, error) {
	rows, err := s.Q.ExportFavorites(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("export favorites: %w", err)
	}
	ids := map[string][]uuid.UUID{}
	seen := map[uuid.UUID]bool{}
	var unique []uuid.UUID
	for _, r := range rows {
		switch r.Kind {
		case "film", "show", "anime", "manga", "book", "album":
		default:
			continue
		}
		ids[r.Kind] = append(ids[r.Kind], r.TitleID)
		if !seen[r.TitleID] {
			seen[r.TitleID] = true
			unique = append(unique, r.TitleID)
		}
	}
	titles, err := s.titles(ctx, unique)
	if err != nil {
		return nil, err
	}
	out := map[string][]core.Title{}
	for kind, list := range ids {
		for _, id := range list {
			if t, ok := titles[id]; ok {
				out[kind] = append(out[kind], t)
			}
		}
	}
	return out, nil
}

// Avatar is the user's avatar JPEG, nil without one.
func (s *Service) Avatar(ctx context.Context, userID uuid.UUID) ([]byte, error) {
	rows, err := s.Q.ExportAvatar(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("export avatar: %w", err)
	}
	if len(rows) == 0 {
		return nil, nil
	}
	return rows[0], nil
}

// MARK: CSV

// CSVHeader is the columns Aaru's own "Any site" import reads (GenericCSVParser), so an export
// re-imports.
var CSVHeader = []string{
	"Title", "Year", "Type", "Status", "Rating", "Owned", "Finished", "Added", "IMDb ID", "TMDB ID",
	"TVDB ID", "MAL ID", "AniList ID", "ISBN", "MusicBrainz ID", "Watched Episodes", "Notes",
}

// CSV is the library as CSV: CRLF line ends, a trailing CRLF, days in UTC.
func (a Account) CSV() string {
	day := func(t time.Time) string { return t.UTC().Format(time.DateOnly) }
	var b strings.Builder
	writeRow := func(fields []string) {
		for i, f := range fields {
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(Field(f))
		}
		b.WriteString("\r\n")
	}
	writeRow(CSVHeader)
	for _, e := range a.Entries {
		t, item, ids := e.Title, e.Item, e.Title.IDs
		year, kind, rating, owned, finished := "", string(t.Type), "", "", ""
		if t.Year != nil {
			year = strconv.Itoa(*t.Year)
		}
		if t.IsAnime {
			kind = "anime"
		}
		if item.Rating != nil {
			rating = Number(item.Rating.Value())
		}
		if item.IsOwned {
			owned = "yes"
		}
		if item.FinishedAt != nil {
			finished = day(*item.FinishedAt)
		}
		watched := make([]string, 0, len(a.Watched[item.ID]))
		for _, k := range a.Watched[item.ID] {
			watched = append(watched, fmt.Sprintf("S%02dE%02d", k.Season, k.Episode))
		}
		notes := ""
		if item.Notes != nil {
			notes = *item.Notes
		}
		writeRow([]string{
			t.Title, year, kind, StatusWord(item.Status), rating, owned, finished, day(item.AddedAt),
			ids.IMDB, ids.TMDB, ids.TVDB, ids.MAL, ids.AniList, ids.ISBN, ids.MusicBrainz,
			strings.Join(watched, " "), notes,
		})
	}
	return b.String()
}

// StatusWord is the word the generic importer maps back to the same status.
func StatusWord(s core.LibraryStatus) string {
	switch s {
	case core.StatusWishlist:
		return "Plan to watch"
	case core.StatusInProgress:
		return "Watching"
	case core.StatusOnHold:
		return "On hold"
	case core.StatusFinished:
		return "Completed"
	case core.StatusDropped:
		return "Dropped"
	}
	return ""
}

// Number is a rating without a trailing ".0".
func Number(v float64) string {
	return strconv.FormatFloat(v, 'f', -1, 64)
}

// Field is one RFC 4180 field: quoted when it holds a comma, quote or line break, inner quotes
// doubled. A leading `=`, `+`, `-` or `@` is prefixed with `'` so a spreadsheet never runs it as
// a formula.
func Field(value string) string {
	if value != "" && strings.ContainsRune("=+-@", rune(value[0])) {
		value = "'" + value
	}
	if !strings.ContainsAny(value, ",\"\n\r") {
		return value
	}
	return `"` + strings.ReplaceAll(value, `"`, `""`) + `"`
}
