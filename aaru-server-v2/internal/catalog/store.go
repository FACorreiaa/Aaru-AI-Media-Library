package catalog

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrTitleConflict is an insert that hit another title's external id. It renders
// as 409 `conflict`, as Swift's StoreConflict did.
var ErrTitleConflict = apperr.Conflict("Another title already has one of these external ids.")

// State is a title's hydration state.
type State struct {
	Status             *TitleStatus
	RuntimeMinutes     *int
	EpisodesHydratedAt *time.Time
	// TracksHydratedAt is, for albums, when the tracklist was last fetched; nil when never.
	TracksHydratedAt *time.Time
}

// AnimeMapping is a community mapping from an AniList entry to TMDB (CAT-009).
// Catalog data, no user.
type AnimeMapping struct {
	AniList    string
	MAL        *string
	AniDB      *string
	TVDB       *string
	TMDB       *string
	TMDBSeason *int
}

// TitleAiring is a show's lifecycle and its next episode to air, for list rows (LST-003).
type TitleAiring struct {
	Status *TitleStatus
	Next   *Episode
}

// AlbumTrack is one track of an album's tracklist.
type AlbumTrack struct {
	Disc     int
	Position int
	Name     string
	LengthMs *int
}

// Key is one provider id on a title of one type. TMDB reuses numbers across movies
// and shows, so the type is part of the key.
type Key struct {
	Type     core.MediaType
	Provider KeyProvider
	ID       string
}

// KeyProvider is a provider a Discover hit is keyed by.
type KeyProvider string

// The providers Discover hits are keyed by.
const (
	KeyTMDB        KeyProvider = "tmdb"
	KeyAniList     KeyProvider = "anilist"
	KeyMusicBrainz KeyProvider = "musicbrainz"
	KeyOpenLibrary KeyProvider = "open_library"
)

// Keys are the hit's provider keys, for the "in library" mark.
func (h Hit) Keys() []Key {
	var keys []Key
	for _, c := range []struct {
		p  KeyProvider
		id string
	}{{KeyTMDB, h.IDs.TMDB}, {KeyAniList, h.IDs.AniList}, {KeyOpenLibrary, h.IDs.OpenLibrary}, {KeyMusicBrainz, h.IDs.MusicBrainz}} {
		if c.id != "" {
			keys = append(keys, Key{Type: h.Type, Provider: c.p, ID: c.id})
		}
	}
	return keys
}

// Store is the titles, episodes, tracks and anime mappings (TitleStore and
// AnimeMappingStore). Build it on a pool, or with WithTx inside a transaction.
type Store struct {
	pool *pgxpool.Pool
	q    *sqlc.Queries
}

// NewStore builds the store.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool, q: sqlc.New(pool)}
}

func i32(p *int) *int32 {
	if p == nil {
		return nil
	}
	v := int32(*p) //nolint:gosec // catalog counts and years are small
	return &v
}

func iptr(p *int32) *int {
	if p == nil {
		return nil
	}
	v := int(*p)
	return &v
}

func sptr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func sval(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func statusPtr(p *string) *TitleStatus {
	if p == nil {
		return nil
	}
	switch s := TitleStatus(*p); s {
	case StatusUpcoming, StatusReturning, StatusEnded, StatusCanceled:
		return &s
	}
	return nil
}

func statusText(s *TitleStatus) *string {
	if s == nil {
		return nil
	}
	v := string(*s)
	return &v
}

// TitleFromRow maps a `titles` row to a core.Title; false for an unknown type.
func TitleFromRow(row sqlc.Title) (core.Title, bool) {
	t := core.MediaType(row.Type)
	if !t.Valid() {
		return core.Title{}, false
	}
	return core.Title{
		ID: row.ID, Type: t, Title: row.Title, OriginalTitle: row.OriginalTitle, Year: iptr(row.Year),
		Synopsis: row.Synopsis, PosterURL: row.PosterUrl, BackdropURL: row.BackdropUrl, Network: row.Network,
		Byline: row.Byline, PageCount: iptr(row.PageCount), ChapterCount: iptr(row.ChapterCount),
		VolumeCount: iptr(row.VolumeCount), IsAnime: row.IsAnime,
		IDs: core.ExternalIDs{
			TMDB: sval(row.Tmdb), IMDB: sval(row.Imdb), Trakt: sval(row.Trakt), TVDB: sval(row.Tvdb),
			ISBN: sval(row.Isbn), OpenLibrary: sval(row.OpenLibrary), AniList: sval(row.Anilist),
			MAL: sval(row.Mal), AniDB: sval(row.Anidb), MusicBrainz: sval(row.Musicbrainz),
		},
	}, true
}

// Insert saves a new title. ErrTitleConflict when another title already holds one
// of its external ids.
func (s *Store) Insert(ctx context.Context, t core.Title, status *TitleStatus, runtimeMinutes *int, genres []string) error {
	if err := t.Validate(); err != nil {
		return err
	}
	if genres == nil {
		genres = []string{}
	}
	ids := t.IDs
	err := s.q.InsertTitle(ctx, sqlc.InsertTitleParams{
		ID: t.ID, Type: string(t.Type), Title: t.Title, OriginalTitle: t.OriginalTitle, Year: i32(t.Year),
		Synopsis: t.Synopsis, PosterUrl: t.PosterURL, BackdropUrl: t.BackdropURL, Network: t.Network,
		Byline: t.Byline, PageCount: i32(t.PageCount), ChapterCount: i32(t.ChapterCount),
		VolumeCount: i32(t.VolumeCount),
		Tmdb:        sptr(ids.TMDB), Imdb: sptr(ids.IMDB), Trakt: sptr(ids.Trakt), Tvdb: sptr(ids.TVDB),
		Isbn: sptr(ids.ISBN), OpenLibrary: sptr(ids.OpenLibrary), Anilist: sptr(ids.AniList), Mal: sptr(ids.MAL),
		Anidb: sptr(ids.AniDB), Musicbrainz: sptr(ids.MusicBrainz),
		IsAnime: t.IsAnime, Status: statusText(status), RuntimeMinutes: i32(runtimeMinutes), Genres: genres,
	})
	if db.IsUniqueViolation(err, "") {
		return ErrTitleConflict
	}
	if err != nil {
		return fmt.Errorf("insert title: %w", err)
	}
	return nil
}

// Title is the title with this id, or nil.
func (s *Store) Title(ctx context.Context, id uuid.UUID) (*core.Title, error) {
	row, err := s.q.TitleByID(ctx, id)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, fmt.Errorf("title: %w", err)
	}
	t, ok := TitleFromRow(row)
	if !ok {
		return nil, nil //nolint:nilnil // nil: not known
	}
	return &t, nil
}

// Find is the title of this type holding any of these ids. TMDB/Trakt ids are type-scoped.
func (s *Store) Find(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*core.Title, error) {
	if ids.IsEmpty() {
		return nil, nil //nolint:nilnil // nil: not known
	}
	row, err := s.q.FindTitle(ctx, sqlc.FindTitleParams{
		Type: string(mediaType), Tmdb: sptr(ids.TMDB), Imdb: sptr(ids.IMDB), Trakt: sptr(ids.Trakt),
		Tvdb: sptr(ids.TVDB), Isbn: sptr(ids.ISBN), OpenLibrary: sptr(ids.OpenLibrary), Anilist: sptr(ids.AniList),
		Mal: sptr(ids.MAL), Anidb: sptr(ids.AniDB), Musicbrainz: sptr(ids.MusicBrainz),
	})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, fmt.Errorf("find title: %w", err)
	}
	t, ok := TitleFromRow(row)
	if !ok {
		return nil, nil //nolint:nilnil // nil: not known
	}
	return &t, nil
}

func fillParams(id uuid.UUID, ids core.ExternalIDs) sqlc.FillTitleIDsParams {
	return sqlc.FillTitleIDsParams{
		ID: id, Tmdb: sptr(ids.TMDB), Imdb: sptr(ids.IMDB), Trakt: sptr(ids.Trakt), Tvdb: sptr(ids.TVDB),
		Isbn: sptr(ids.ISBN), OpenLibrary: sptr(ids.OpenLibrary), Anilist: sptr(ids.AniList), Mal: sptr(ids.MAL),
		Anidb: sptr(ids.AniDB), Musicbrainz: sptr(ids.MusicBrainz),
	}
}

// FillIDs is fill-empty-only. An id another title already holds is skipped, never merged.
//
// Usually one statement fills every empty id (an import calls this per matched
// row). Only when another title already holds one of them does it fall back to id
// by id, so the rest still land.
func (s *Store) FillIDs(ctx context.Context, id uuid.UUID, ids core.ExternalIDs) error {
	if ids.IsEmpty() {
		return nil
	}
	err := s.q.FillTitleIDs(ctx, fillParams(id, ids))
	if err == nil {
		return nil
	}
	if !db.IsUniqueViolation(err, "") {
		return fmt.Errorf("fill title ids: %w", err)
	}
	for _, known := range ids.Known() {
		var one core.ExternalIDs
		setID(&one, known.Provider, known.Value)
		if err := s.q.FillTitleIDs(ctx, fillParams(id, one)); err != nil && !db.IsUniqueViolation(err, "") {
			return fmt.Errorf("fill title id %s: %w", known.Provider, err)
		}
	}
	return nil
}

func setID(ids *core.ExternalIDs, provider, value string) {
	switch provider {
	case "tmdb":
		ids.TMDB = value
	case "imdb":
		ids.IMDB = value
	case "trakt":
		ids.Trakt = value
	case "tvdb":
		ids.TVDB = value
	case "isbn":
		ids.ISBN = value
	case "openLibrary":
		ids.OpenLibrary = value
	case "anilist":
		ids.AniList = value
	case "mal":
		ids.MAL = value
	case "anidb":
		ids.AniDB = value
	case "musicbrainz":
		ids.MusicBrainz = value
	}
}

// State is the title's hydration state, or nil when there is no such title.
func (s *Store) State(ctx context.Context, id uuid.UUID) (*State, error) {
	row, err := s.q.TitleByID(ctx, id)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, fmt.Errorf("catalog state: %w", err)
	}
	return &State{
		Status: statusPtr(row.Status), RuntimeMinutes: iptr(row.RuntimeMinutes),
		EpisodesHydratedAt: row.EpisodesHydratedAt, TracksHydratedAt: row.TracksHydratedAt,
	}, nil
}

// Titles are the titles with these ids, in the order given; unknown ids are skipped.
func (s *Store) Titles(ctx context.Context, ids []uuid.UUID) ([]core.Title, error) {
	if len(ids) == 0 {
		return []core.Title{}, nil
	}
	rows, err := s.q.TitlesByIDs(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("titles: %w", err)
	}
	byID := make(map[uuid.UUID]core.Title, len(rows))
	for _, row := range rows {
		if t, ok := TitleFromRow(row); ok {
			byID[t.ID] = t
		}
	}
	out := make([]core.Title, 0, len(ids))
	for _, id := range ids {
		if t, ok := byID[id]; ok {
			out = append(out, t)
		}
	}
	return out, nil
}

// Airing is the status and first unaired episode of each show among these ids;
// other types are left out.
//
// pgx directly: sqlc reads the LATERAL subquery's columns as non-null, but a show
// with nothing to air has none.
func (s *Store) Airing(ctx context.Context, ids []uuid.UUID, now time.Time) (map[uuid.UUID]TitleAiring, error) {
	out := map[uuid.UUID]TitleAiring{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `
SELECT t.id, t.status, next.season, next.episode, next.name, next.airs_at, next.airs_at_exact
FROM titles t
LEFT JOIN LATERAL (
    SELECT se.season, se.episode, se.name, se.airs_at, se.airs_at_exact FROM show_episodes se
    WHERE se.title_id = t.id AND se.season > 0 AND se.airs_at > $2
    ORDER BY se.airs_at, se.season, se.episode LIMIT 1
) next ON true
WHERE t.type = 'show' AND t.id = ANY($1::uuid[])`, ids, now)
	if err != nil {
		return nil, fmt.Errorf("airing: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var (
			id              uuid.UUID
			status, name    *string
			season, episode *int
			airsAt          *time.Time
			exact           *bool
		)
		if err := rows.Scan(&id, &status, &season, &episode, &name, &airsAt, &exact); err != nil {
			return nil, fmt.Errorf("airing row: %w", err)
		}
		a := TitleAiring{Status: statusPtr(status)}
		if season != nil && episode != nil {
			a.Next = &Episode{Season: *season, Episode: *episode, Name: name, AirsAt: airsAt, AirTimeKnown: exact != nil && *exact}
		}
		out[id] = a
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("airing rows: %w", err)
	}
	return out, nil
}

// StaleTrackedShows are shows someone tracks (wishlist or in progress, or on a list)
// whose episodes were never loaded or are past their staleness window,
// never-loaded first. Shows attempted since retryAfter are skipped so a failing
// provider is not hammered.
func (s *Store) StaleTrackedShows(ctx context.Context, now, retryAfter time.Time, limit int) ([]uuid.UUID, error) {
	airingStale := now.Add(-AiringStaleness)
	dormantStale := now.Add(-DormantStaleness)
	windowStart := now.Add(-AiringWindow)
	windowEnd := now.Add(AiringWindow)
	ids, err := s.q.StaleTrackedShows(ctx, sqlc.StaleTrackedShowsParams{
		RetryAfter: &retryAfter, DormantStale: &dormantStale, AiringStale: &airingStale,
		WindowStart: &windowStart, WindowEnd: &windowEnd, Lim: int32(limit), //nolint:gosec // small pass limit
	})
	if err != nil {
		return nil, fmt.Errorf("stale tracked shows: %w", err)
	}
	return ids, nil
}

// MarkEpisodesAttempted records an episode refresh attempt, successful or not.
func (s *Store) MarkEpisodesAttempted(ctx context.Context, id uuid.UUID, at time.Time) error {
	if err := s.q.MarkEpisodesAttempted(ctx, sqlc.MarkEpisodesAttemptedParams{ID: id, At: &at}); err != nil {
		return fmt.Errorf("mark episodes attempted: %w", err)
	}
	return nil
}

// ShowEpisodes are a show's stored episodes, by season then episode.
func (s *Store) ShowEpisodes(ctx context.Context, id uuid.UUID) ([]Episode, error) {
	rows, err := s.q.ShowEpisodes(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("show episodes: %w", err)
	}
	out := make([]Episode, 0, len(rows))
	for _, r := range rows {
		out = append(out, Episode{
			Season: int(r.Season), Episode: int(r.Episode), Name: r.Name, AirsAt: r.AirsAt,
			RuntimeMinutes: iptr(r.RuntimeMinutes), TMDBEpisodeID: r.TmdbEpisodeID, AirTimeKnown: r.AirsAtExact,
			Overview: r.Overview, StillURL: r.StillUrl,
		})
	}
	return out, nil
}

// episodeChunk is rows per upsert statement.
const episodeChunk = 500

// SaveEpisodes upserts episodes by (season, episode) and records the show's status
// and when it was hydrated, in one transaction. Never deletes: progress refers to
// episodes by number. A provider's repeated episode keeps its last copy.
//
// pgx directly: the bulk upsert binds arrays with null elements, which sqlc's
// unnest parameters cannot carry.
func (s *Store) SaveEpisodes(ctx context.Context, id uuid.UUID, fresh Episodes, hydratedAt time.Time) error {
	seen := map[[2]int]bool{}
	var episodes []Episode
	for i := len(fresh.Episodes) - 1; i >= 0; i-- {
		e := fresh.Episodes[i]
		if k := [2]int{e.Season, e.Episode}; !seen[k] {
			seen[k] = true
			episodes = append(episodes, e)
		}
	}
	slices.Reverse(episodes)
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		for start := 0; start < len(episodes); start += episodeChunk {
			chunk := episodes[start:min(start+episodeChunk, len(episodes))]
			var (
				rowIDs           = make([]uuid.UUID, len(chunk))
				seasons, numbers = make([]int32, len(chunk)), make([]int32, len(chunk))
				names, overviews = make([]*string, len(chunk)), make([]*string, len(chunk))
				airs             = make([]*time.Time, len(chunk))
				exact            = make([]bool, len(chunk))
				runtimes         = make([]*int32, len(chunk))
				tmdbIDs, stills  = make([]*string, len(chunk)), make([]*string, len(chunk))
			)
			for i, e := range chunk {
				rowIDs[i] = uuid.New()
				seasons[i], numbers[i] = int32(e.Season), int32(e.Episode) //nolint:gosec // episode numbers are small
				names[i], overviews[i], airs[i], exact[i] = e.Name, e.Overview, e.AirsAt, e.AirTimeKnown
				runtimes[i], tmdbIDs[i], stills[i] = i32(e.RuntimeMinutes), e.TMDBEpisodeID, e.StillURL
			}
			_, err := tx.Exec(ctx, `
INSERT INTO show_episodes
    (id, title_id, season, episode, name, overview, airs_at, airs_at_exact, runtime_minutes, tmdb_episode_id, still_url)
SELECT u.id, $1, u.season, u.episode, u.name, u.overview, u.airs_at, u.airs_at_exact, u.runtime_minutes,
       u.tmdb_episode_id, u.still_url
FROM unnest($2::uuid[], $3::int[], $4::int[], $5::text[], $6::text[], $7::timestamptz[], $8::bool[], $9::int[],
            $10::text[], $11::text[])
    AS u(id, season, episode, name, overview, airs_at, airs_at_exact, runtime_minutes, tmdb_episode_id, still_url)
ON CONFLICT (title_id, season, episode) DO UPDATE SET
    name = EXCLUDED.name, overview = EXCLUDED.overview,
    airs_at = EXCLUDED.airs_at, airs_at_exact = EXCLUDED.airs_at_exact,
    runtime_minutes = EXCLUDED.runtime_minutes, tmdb_episode_id = EXCLUDED.tmdb_episode_id,
    still_url = EXCLUDED.still_url`,
				id, rowIDs, seasons, numbers, names, overviews, airs, exact, runtimes, tmdbIDs, stills)
			if err != nil {
				return fmt.Errorf("upsert episodes: %w", err)
			}
		}
		err := sqlc.New(tx).StampEpisodesHydrated(ctx, sqlc.StampEpisodesHydratedParams{
			ID: id, BackdropUrl: fresh.BackdropURL, Network: fresh.Network, HydratedAt: &hydratedAt,
			Status: statusText(fresh.Status),
		})
		if err != nil {
			return fmt.Errorf("stamp episodes: %w", err)
		}
		return nil
	})
}

// SaveTracks replaces an album's tracklist whole (MUS-001), in one transaction.
//
// pgx directly for the insert: lengths are a nullable array sqlc cannot bind.
func (s *Store) SaveTracks(ctx context.Context, id uuid.UUID, tracks []AlbumTrack, hydratedAt time.Time) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		q := sqlc.New(tx)
		if err := q.DeleteAlbumTracks(ctx, id); err != nil {
			return fmt.Errorf("delete tracks: %w", err)
		}
		if len(tracks) > 0 {
			discs, positions := make([]int32, len(tracks)), make([]int32, len(tracks))
			names, lengths := make([]string, len(tracks)), make([]*int32, len(tracks))
			for i, t := range tracks {
				discs[i], positions[i] = int32(t.Disc), int32(t.Position) //nolint:gosec // small
				names[i], lengths[i] = t.Name, i32(t.LengthMs)
			}
			_, err := tx.Exec(ctx, `
INSERT INTO album_tracks (title_id, disc, position, name, length_ms)
SELECT $1, u.disc, u.position, u.name, u.length_ms
FROM unnest($2::int[], $3::int[], $4::text[], $5::int[]) AS u(disc, position, name, length_ms)
ON CONFLICT (title_id, disc, position) DO NOTHING`, id, discs, positions, names, lengths)
			if err != nil {
				return fmt.Errorf("insert tracks: %w", err)
			}
		}
		if err := q.StampTracksHydrated(ctx, sqlc.StampTracksHydratedParams{ID: id, HydratedAt: &hydratedAt}); err != nil {
			return fmt.Errorf("stamp tracks: %w", err)
		}
		return nil
	})
}

// Tracks is an album's stored tracklist, by disc then position.
func (s *Store) Tracks(ctx context.Context, id uuid.UUID) ([]AlbumTrack, error) {
	rows, err := s.q.AlbumTracks(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("album tracks: %w", err)
	}
	out := make([]AlbumTrack, 0, len(rows))
	for _, r := range rows {
		out = append(out, AlbumTrack{Disc: int(r.Disc), Position: int(r.Position), Name: r.Name, LengthMs: iptr(r.LengthMs)})
	}
	return out, nil
}

// TitlesMissingGenres is CAT-018's backfill queue: films, shows and anime in
// someone's library or on a list with no genres, not tried since retryAfter, oldest first.
func (s *Store) TitlesMissingGenres(ctx context.Context, retryAfter time.Time, limit int) ([]core.Title, error) {
	rows, err := s.q.TitlesMissingGenres(ctx, sqlc.TitlesMissingGenresParams{RetryAfter: &retryAfter, Lim: int32(limit)}) //nolint:gosec // small
	if err != nil {
		return nil, fmt.Errorf("titles missing genres: %w", err)
	}
	out := make([]core.Title, 0, len(rows))
	for _, row := range rows {
		if t, ok := TitleFromRow(row); ok {
			out = append(out, t)
		}
	}
	return out, nil
}

// FillGenres stores genres when the title has none yet, and stamps the attempt either way.
func (s *Store) FillGenres(ctx context.Context, id uuid.UUID, genres []string, attemptedAt time.Time) error {
	if genres == nil {
		genres = []string{}
	}
	if err := s.q.FillGenres(ctx, sqlc.FillGenresParams{ID: id, Genres: genres, AttemptedAt: &attemptedAt}); err != nil {
		return fmt.Errorf("fill genres: %w", err)
	}
	return nil
}

// Genres are the title's stored genres.
func (s *Store) Genres(ctx context.Context, id uuid.UUID) ([]string, error) {
	genres, err := s.q.TitleGenres(ctx, id)
	if db.IsNoRows(err) {
		return []string{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("title genres: %w", err)
	}
	return genres, nil
}

// BooksMissingPageCount is APP-017's queue: shelved books with no page count,
// in-progress first, not tried since retryAfter.
func (s *Store) BooksMissingPageCount(ctx context.Context, retryAfter time.Time, limit int) ([]core.Title, error) {
	ids, err := s.q.BooksMissingPageCount(ctx, sqlc.BooksMissingPageCountParams{RetryAfter: &retryAfter, Lim: int32(limit)}) //nolint:gosec // small
	if err != nil {
		return nil, fmt.Errorf("books missing page count: %w", err)
	}
	return s.Titles(ctx, ids)
}

// FillPageCount stores a page count when none is set yet, and stamps the attempt either way.
func (s *Store) FillPageCount(ctx context.Context, id uuid.UUID, pageCount *int, attemptedAt time.Time) error {
	if err := s.q.FillPageCount(ctx, sqlc.FillPageCountParams{ID: id, PageCount: i32(pageCount), AttemptedAt: &attemptedAt}); err != nil {
		return fmt.Errorf("fill page count: %w", err)
	}
	return nil
}

func mappingFromRow(r sqlc.AnimeMapping) AnimeMapping {
	return AnimeMapping{AniList: r.Anilist, MAL: r.Mal, AniDB: r.Anidb, TVDB: r.Tvdb, TMDB: r.Tmdb, TMDBSeason: iptr(r.TmdbSeason)}
}

func mappingsFromRows(rows []sqlc.AnimeMapping) []AnimeMapping {
	out := make([]AnimeMapping, 0, len(rows))
	for _, r := range rows {
		out = append(out, mappingFromRow(r))
	}
	return out
}

// MappingByAniList is the mapping for this AniList id, or nil.
func (s *Store) MappingByAniList(ctx context.Context, anilist string) (*AnimeMapping, error) {
	row, err := s.q.AnimeMappingByAniList(ctx, anilist)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, fmt.Errorf("anime mapping: %w", err)
	}
	m := mappingFromRow(row)
	return &m, nil
}

// MappingByMAL is the first mapping with this MAL id: a MAL export carries no AniList id.
func (s *Store) MappingByMAL(ctx context.Context, mal string) (*AnimeMapping, error) {
	row, err := s.q.AnimeMappingByMAL(ctx, &mal)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, fmt.Errorf("anime mapping by mal: %w", err)
	}
	m := mappingFromRow(row)
	return &m, nil
}

// MappingsByAniList are the mappings known for any of these AniList ids, in one query.
func (s *Store) MappingsByAniList(ctx context.Context, ids []string) ([]AnimeMapping, error) {
	if len(ids) == 0 {
		return []AnimeMapping{}, nil
	}
	rows, err := s.q.AnimeMappingsByAniList(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("anime mappings: %w", err)
	}
	return mappingsFromRows(rows), nil
}

// MappingsByMAL is MappingByMAL for many MAL ids in one query, keyed by MAL id.
func (s *Store) MappingsByMAL(ctx context.Context, ids []string) (map[string]AnimeMapping, error) {
	out := map[string]AnimeMapping{}
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := s.q.AnimeMappingsByMAL(ctx, unique(ids))
	if err != nil {
		return nil, fmt.Errorf("anime mappings by mal: %w", err)
	}
	for _, r := range rows {
		if r.Mal != nil {
			if _, ok := out[*r.Mal]; !ok {
				out[*r.Mal] = mappingFromRow(r)
			}
		}
	}
	return out, nil
}

// MappingsByTMDB is every mapping onto these TMDB shows: one per AniList entry, so a
// show's seasons (SCR-005).
func (s *Store) MappingsByTMDB(ctx context.Context, ids []string) ([]AnimeMapping, error) {
	if len(ids) == 0 {
		return []AnimeMapping{}, nil
	}
	rows, err := s.q.AnimeMappingsByTMDB(ctx, unique(ids))
	if err != nil {
		return nil, fmt.Errorf("anime mappings by tmdb: %w", err)
	}
	return mappingsFromRows(rows), nil
}

// UpsertMapping inserts or replaces one mapping.
func (s *Store) UpsertMapping(ctx context.Context, m AnimeMapping) error {
	return upsertMapping(ctx, s.q, m)
}

func upsertMapping(ctx context.Context, q *sqlc.Queries, m AnimeMapping) error {
	err := q.UpsertAnimeMapping(ctx, sqlc.UpsertAnimeMappingParams{
		Anilist: m.AniList, Mal: m.MAL, Anidb: m.AniDB, Tvdb: m.TVDB, Tmdb: m.TMDB, TmdbSeason: i32(m.TMDBSeason),
	})
	if err != nil {
		return fmt.Errorf("upsert anime mapping: %w", err)
	}
	return nil
}

// mappingBatch is rows per upsert statement.
const mappingBatch = 1000

// UpsertMappings upserts in batches inside one transaction; re-running with the same
// rows changes nothing.
//
// pgx directly: a bulk unnest with nullable columns sqlc cannot bind.
func (s *Store) UpsertMappings(ctx context.Context, mappings []AnimeMapping) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		for start := 0; start < len(mappings); start += mappingBatch {
			batch := mappings[start:min(start+mappingBatch, len(mappings))]
			// One statement cannot upsert a key twice: the last row per AniList id wins.
			last := map[string]int{}
			for i, m := range batch {
				last[m.AniList] = i
			}
			var anilist []string
			var mal, anidb, tvdb, tmdb []*string
			var season []*int32
			for i, m := range batch {
				if last[m.AniList] != i {
					continue
				}
				anilist = append(anilist, m.AniList)
				mal, anidb, tvdb, tmdb = append(mal, m.MAL), append(anidb, m.AniDB), append(tvdb, m.TVDB), append(tmdb, m.TMDB)
				season = append(season, i32(m.TMDBSeason))
			}
			_, err := tx.Exec(ctx, `
INSERT INTO anime_mappings (anilist, mal, anidb, tvdb, tmdb, tmdb_season)
SELECT * FROM unnest($1::text[], $2::text[], $3::text[], $4::text[], $5::text[], $6::int[])
ON CONFLICT (anilist) DO UPDATE SET
    mal = EXCLUDED.mal, anidb = EXCLUDED.anidb, tvdb = EXCLUDED.tvdb,
    tmdb = EXCLUDED.tmdb, tmdb_season = EXCLUDED.tmdb_season`, anilist, mal, anidb, tvdb, tmdb, season)
			if err != nil {
				return fmt.Errorf("upsert anime mappings: %w", err)
			}
		}
		return nil
	})
}

// LibraryItemIDs are the user's items among titles carrying these provider ids:
// Discover's "in library" mark.
func (s *Store) LibraryItemIDs(ctx context.Context, userID uuid.UUID, keys []Key) (map[Key]uuid.UUID, error) {
	found := map[Key]uuid.UUID{}
	if len(keys) == 0 {
		return found, nil
	}
	wanted := map[Key]bool{}
	ids := map[KeyProvider][]string{}
	for _, k := range keys {
		wanted[k] = true
		ids[k.Provider] = append(ids[k.Provider], k.ID)
	}
	nonNil := func(v []string) []string {
		if v == nil {
			return []string{}
		}
		return v
	}
	rows, err := s.q.LibraryItemsMatchingCatalog(ctx, sqlc.LibraryItemsMatchingCatalogParams{
		UserID: userID, Tmdb: nonNil(ids[KeyTMDB]), Anilist: nonNil(ids[KeyAniList]),
		OpenLibrary: nonNil(ids[KeyOpenLibrary]), Musicbrainz: nonNil(ids[KeyMusicBrainz]),
	})
	if err != nil {
		return nil, fmt.Errorf("library items matching catalog: %w", err)
	}
	for _, r := range rows {
		t := core.MediaType(r.Type)
		for _, c := range []struct {
			p  KeyProvider
			id *string
		}{{KeyTMDB, r.Tmdb}, {KeyAniList, r.Anilist}, {KeyOpenLibrary, r.OpenLibrary}, {KeyMusicBrainz, r.Musicbrainz}} {
			if c.id == nil {
				continue
			}
			if k := (Key{Type: t, Provider: c.p, ID: *c.id}); wanted[k] {
				found[k] = r.ID
			}
		}
	}
	return found, nil
}

// LibraryItemID is the user's item for this title, or nil.
func (s *Store) LibraryItemID(ctx context.Context, userID, titleID uuid.UUID) (*uuid.UUID, error) {
	id, err := s.q.LibraryItemIDForTitle(ctx, sqlc.LibraryItemIDForTitleParams{UserID: userID, TitleID: titleID})
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // nil: not known
	}
	if err != nil {
		return nil, fmt.Errorf("library item for title: %w", err)
	}
	return &id, nil
}

func unique(values []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(values))
	for _, v := range values {
		if !seen[v] {
			seen[v] = true
			out = append(out, v)
		}
	}
	return out
}
