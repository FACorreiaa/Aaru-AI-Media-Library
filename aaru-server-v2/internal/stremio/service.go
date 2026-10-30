package stremio

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/schedule"
	"aaru-go-api/internal/scrobble"
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Paging and the manifest's fixed values.
const (
	PageSize = 100
	// MaxSkip is the wishlist depth Stremio may ask for, in items.
	MaxSkip      = 2000
	ConfigureURL = "https://aaruapp.com/app/settings/connected"
)

// Types is the Stremio types the addon serves.
var Types = []string{"movie", "series"}

// TheManifest is the addon's manifest.
var TheManifest = func() Manifest {
	logo := "https://aaruapp.com/icon-512.png"
	skip := []CatalogExtra{{Name: "skip"}}
	return Manifest{
		ID: "com.aaruapp.library", Version: "1.0.0", Name: "Aaru",
		Description: "Your Aaru library in Stremio: continue watching, the week ahead and what you plan to watch. " +
			"What you watch in Stremio ticks itself off in Aaru.",
		Logo: &logo,
		Resources: []Resource{
			{Name: "catalog", Types: Types},
			{Name: "meta", Types: Types, IDPrefixes: []string{"aaru:"}},
			{Name: "player", Types: Types, IDPrefixes: []string{"tt", "aaru:"}},
			{Name: "library", Types: Types, IDPrefixes: []string{"tt", "aaru:"}},
		},
		Types:      Types,
		IDPrefixes: []string{"tt", "aaru:"},
		Catalogs: []ManifestCatalog{
			{Type: "series", ID: "aaru-continue", Name: "Aaru · Continue watching"},
			{Type: "series", ID: "aaru-week", Name: "Aaru · Next 7 days"},
			// Ids stay `aaru-wishlist` (installed addons keep working); only the name follows APP-014.
			{Type: "series", ID: "aaru-wishlist", Name: "Aaru · Plan to watch", Extra: skip},
			{Type: "movie", ID: "aaru-wishlist", Name: "Aaru · Plan to watch", Extra: skip},
		},
		BehaviorHints: BehaviorHints{Configurable: true, ConfigurationRequired: false},
	}
}()

// Service is the addon's behaviour.
type Service struct {
	Library  *library.Service
	Schedule *schedule.Service
	Catalog  *catalog.Kit
	Scrobble *scrobble.Service
	// EpisodeMap puts Stremio's episode numbers on the TMDB show; nil keeps them as they come.
	EpisodeMap *EpisodeMap
	Now        func() time.Time
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// CatalogRows is one of the three personal catalogs; empty without `library:read` or for an unknown one.
func (s *Service) CatalogRows(ctx context.Context, id, typ string, extra map[string]string, caller auth.AgentCaller) ([]MetaPreview, error) {
	if !caller.Has(auth.ScopeLibraryRead) {
		return []MetaPreview{}, nil
	}
	user := caller.UserID
	switch {
	case id == "aaru-continue" && typ == "series":
		entries, err := s.Schedule.ContinueWatching(ctx, user, s.now(), 50)
		if err != nil {
			return nil, err
		}
		out := make([]MetaPreview, len(entries))
		for i, e := range entries {
			out[i] = Preview(e.Title)
		}
		return out, nil
	case id == "aaru-week" && typ == "series":
		now := s.now()
		entries, err := s.Schedule.Calendar(ctx, user, now, now.Add(7*24*time.Hour))
		if err != nil {
			return nil, err
		}
		seen := map[uuid.UUID]bool{}
		out := []MetaPreview{}
		for _, e := range entries {
			if seen[e.Title.ID] {
				continue
			}
			seen[e.Title.ID] = true
			out = append(out, Preview(e.Title))
		}
		return out, nil
	case id == "aaru-wishlist" && (typ == "series" || typ == "movie"):
		skip, err := strconv.Atoi(extra["skip"])
		if err != nil {
			skip = 0
		}
		skip = min(max(skip, 0), MaxSkip)
		media := core.MediaShow
		if typ == "movie" {
			media = core.MediaMovie
		}
		return s.wishlist(ctx, user, media, skip)
	default:
		return []MetaPreview{}, nil
	}
}

func (s *Service) wishlist(ctx context.Context, user uuid.UUID, media core.MediaType, skip int) ([]MetaPreview, error) {
	status := core.StatusWishlist
	filter := library.Filter{Type: &media, Status: &status}
	var titles []core.Title
	var cursor *string
	for {
		entries, next, err := s.Library.List(ctx, user, filter, cursor, 200)
		if err != nil {
			return nil, err
		}
		for _, e := range entries {
			titles = append(titles, e.Title)
		}
		cursor = next
		if cursor == nil || len(titles) >= skip+PageSize {
			break
		}
	}
	out := []MetaPreview{}
	for i := skip; i < len(titles) && len(out) < PageSize; i++ {
		out = append(out, Preview(titles[i]))
	}
	return out, nil
}

func stremioType(t core.MediaType) string {
	if t == core.MediaMovie {
		return "movie"
	}
	return "series"
}

func yearText(y *int) *string {
	if y == nil {
		return nil
	}
	s := strconv.Itoa(*y)
	return &s
}

// Preview is a title as a catalog row.
func Preview(t core.Title) MetaPreview {
	return MetaPreview{
		ID: ForTitle(t), Type: stremioType(t.Type), Name: t.Title, Poster: t.PosterURL, Background: t.BackdropURL,
		Description: t.Synopsis, ReleaseInfo: yearText(t.Year),
	}
}

// undated is 2100-01-01: Stremio requires a date, and an undated episode sorts as not yet released.
var undated = time.Unix(4_102_444_800, 0).UTC()

// Meta is details for an `aaru:` title (Cinemeta serves `tt` ones); nil when unknown.
func (s *Service) Meta(ctx context.Context, raw string, caller auth.AgentCaller) (*Meta, error) {
	if !caller.Has(auth.ScopeLibraryRead) {
		return nil, nil //nolint:nilnil // unknown to this caller
	}
	id, ok := ParseID(raw)
	if !ok || id.TitleID == nil {
		return nil, nil //nolint:nilnil // not an Aaru id
	}
	detail, err := s.Catalog.Service.Detail(ctx, *id.TitleID)
	if err != nil {
		var ae *apperr.Error
		if errors.As(err, &ae) && ae.Status == http.StatusNotFound {
			return nil, nil //nolint:nilnil // unknown title
		}
		return nil, err
	}
	t := detail.Title
	base := "aaru:" + strings.ToLower(id.TitleID.String())
	meta := &Meta{
		ID: base, Type: stremioType(t.Type), Name: t.Title, Poster: t.PosterURL, Background: t.BackdropURL,
		Description: t.Synopsis, ReleaseInfo: yearText(t.Year),
	}
	if detail.Episodes != nil {
		videos := make([]MetaVideo, len(detail.Episodes))
		for i, e := range detail.Episodes {
			name := fmt.Sprintf("Episode %d", e.Episode)
			if e.Name != nil {
				name = *e.Name
			}
			released := undated
			if e.AirsAt != nil {
				released = *e.AirsAt
			}
			videos[i] = MetaVideo{
				ID: fmt.Sprintf("%s:%d:%d", base, e.Season, e.Episode), Title: name, Season: e.Season,
				Episode: e.Episode, Released: released.UTC().Format("2006-01-02T15:04:05Z"),
				Thumbnail: e.StillURL, Overview: e.Overview,
			}
		}
		meta.Videos = &videos
	}
	return meta, nil
}

// EventResult is what an event did.
type EventResult int

// The results.
const (
	Accepted EventResult = iota + 1
	Forbidden
	Ignored
)

// MediaType is the Aaru type of a Stremio type; false for anything else.
func MediaType(stremio string) (core.MediaType, bool) {
	switch stremio {
	case "movie":
		return core.MediaMovie, true
	case "series":
		return core.MediaShow, true
	default:
		return "", false
	}
}

// Player is Stremio core 0.64's `player` event: start, pause or stop with position and duration (ms).
func (s *Service) Player(ctx context.Context, typ, videoID string, extra map[string]string, caller auth.AgentCaller) (EventResult, error) {
	if !caller.Has(auth.ScopeScrobbleWrite) {
		return Forbidden, nil
	}
	media, ok := MediaType(typ)
	if !ok {
		return Ignored, nil
	}
	id, ok := ParseID(videoID)
	if !ok {
		return Ignored, nil
	}
	action, ok := scrobble.ParseAction(extra["action"])
	if !ok {
		return Ignored, nil
	}
	if media == core.MediaShow && id.Episode == nil {
		return Ignored, nil
	}
	titleID, ids := id.Ref()
	var episode *core.EpisodeKey
	if media == core.MediaShow {
		episode = id.Episode
	}
	if episode != nil {
		title, mapped, found, err := s.onShow(ctx, []core.EpisodeKey{*episode}, id)
		if err != nil {
			return 0, err
		}
		if found {
			if len(mapped) == 0 {
				return Ignored, nil
			}
			titleID, episode = &title.ID, &mapped[0]
		}
	}
	position, err := strconv.ParseInt(extra["currentTime"], 10, 64)
	if err != nil {
		position = 0
	}
	duration, err := strconv.ParseInt(extra["duration"], 10, 64)
	if err != nil {
		duration = 0
	}
	_, err = s.Scrobble.Report(ctx, scrobble.Report{
		Source: scrobble.SourceStremio, ExternalRef: videoID, Type: media, IDs: ids, TitleID: titleID,
		Episode: episode, Action: action, PositionMs: position, DurationMs: duration,
	}, caller)
	if err != nil {
		return 0, err
	}
	return Accepted, nil
}

// LibraryEvent is Stremio core 0.64's `library` event. `watched` ticks exactly the named episodes (or
// finishes a movie); `unwatched` and `libraryAdd` need the opt-in `library:write`; `libraryRemove` is
// always ignored, because Aaru is the source of truth.
func (s *Service) LibraryEvent(ctx context.Context, typ, metaID string, extra map[string]string, caller auth.AgentCaller) (EventResult, error) {
	media, ok := MediaType(typ)
	if !ok {
		return Ignored, nil
	}
	id, ok := ParseID(metaID)
	if !ok {
		return Ignored, nil
	}
	action, ok := extra["action"]
	if !ok {
		return Ignored, nil
	}
	var named []core.EpisodeKey
	for _, part := range strings.Split(extra["videoId"], ",") {
		if part == "" {
			continue
		}
		other, ok := ParseID(part)
		if !ok || !other.SameBase(id) || other.Episode == nil {
			continue
		}
		named = append(named, *other.Episode)
	}
	titleID, ids := id.Ref()
	ref, episodes, err := s.placed(ctx, named, core.MediaRef{TitleID: titleID, Type: media, IDs: ids}, id)
	if err != nil {
		return 0, err
	}
	switch action {
	case "watched":
		if !caller.Has(auth.ScopeScrobbleWrite) {
			return Forbidden, nil
		}
		if media == core.MediaShow && len(episodes) == 0 {
			return Ignored, nil
		}
		title, err := s.Scrobble.Resolve(ctx, ref)
		if err != nil || title == nil {
			return Ignored, err
		}
		if _, err := s.Scrobble.MarkWatched(ctx, *title, episodes, caller); err != nil {
			return 0, err
		}
		return Accepted, nil
	case "unwatched":
		if !caller.Has(auth.ScopeLibraryWrite) || media != core.MediaShow || len(episodes) == 0 {
			return Ignored, nil
		}
		return s.unwatch(ctx, ref, episodes, caller)
	case "libraryAdd":
		if !caller.Has(auth.ScopeLibraryWrite) {
			return Ignored, nil
		}
		return s.addToWishlist(ctx, ref, caller)
	default:
		return Ignored, nil
	}
}

// placed is what a library event acts on, with Stremio's numbers put on the show. Episodes it cannot
// place drop out.
func (s *Service) placed(ctx context.Context, episodes []core.EpisodeKey, ref core.MediaRef, id ID) (core.MediaRef, []core.EpisodeKey, error) {
	if ref.Type != core.MediaShow {
		return ref, episodes, nil
	}
	title, mapped, found, err := s.onShow(ctx, episodes, id)
	if err != nil || !found {
		return ref, episodes, err
	}
	return core.MediaRef{TitleID: &title.ID, Type: core.MediaShow, IDs: ref.IDs}, mapped, nil
}

// onShow is Stremio's episodes of IMDb series `id` as the matched show numbers them, leaving out any it
// cannot place. found is false when there is nothing to translate: no map, an Aaru id, or no such show.
func (s *Service) onShow(ctx context.Context, keys []core.EpisodeKey, id ID) (core.Title, []core.EpisodeKey, bool, error) {
	if s.EpisodeMap == nil || id.IMDB == "" || len(keys) == 0 {
		return core.Title{}, nil, false, nil
	}
	title, err := s.show(ctx, id.IMDB)
	if err != nil || title == nil || title.Type != core.MediaShow {
		return core.Title{}, nil, false, err
	}
	detail, err := s.Catalog.Service.Detail(ctx, title.ID)
	if err != nil {
		return core.Title{}, nil, false, err
	}
	episodes := []core.EpisodeKey{}
	for _, key := range keys {
		if mapped := s.EpisodeMap.Episode(ctx, key, id.IMDB, *title, detail.Episodes); mapped != nil {
			episodes = append(episodes, *mapped)
		}
	}
	return *title, episodes, true, nil
}

// show is the show Stremio's IMDb series is: by its TVDB id first, then by the IMDb id. TMDB can list an
// arc that TVDB and TMDB's own show keep as a season as an entry of its own: Stremio's `tt14986406`
// (Bleach: Thousand-Year Blood War) finds a near-empty TMDB `336301`, while its TVDB id is Bleach's.
func (s *Service) show(ctx context.Context, imdb string) (*core.Title, error) {
	if tvdb := s.EpisodeMap.TVDB(ctx, imdb); tvdb != nil {
		title, err := s.Scrobble.Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{TVDB: *tvdb}})
		if err != nil {
			return nil, err
		}
		if title != nil {
			return title, nil
		}
	}
	return s.Scrobble.Resolve(ctx, core.MediaRef{Type: core.MediaShow, IDs: core.ExternalIDs{IMDB: imdb}})
}

func (s *Service) unwatch(ctx context.Context, ref core.MediaRef, episodes []core.EpisodeKey, caller auth.AgentCaller) (EventResult, error) {
	title, err := s.Scrobble.Resolve(ctx, ref)
	if err != nil || title == nil {
		return Ignored, err
	}
	item, err := s.Library.ItemForTitle(ctx, caller.UserID, title.ID)
	if err != nil || item == nil {
		return Ignored, err
	}
	if _, err := s.Library.SetEpisodes(ctx, item.Item.ID, caller.UserID, episodes, false, library.AgentCaller(caller.Token)); err != nil {
		return 0, err
	}
	return Accepted, nil
}

// addToWishlist adds as wishlist when absent; never changes the status of a title already in the library.
func (s *Service) addToWishlist(ctx context.Context, ref core.MediaRef, caller auth.AgentCaller) (EventResult, error) {
	title, err := s.Scrobble.Resolve(ctx, ref)
	if err != nil || title == nil {
		return Ignored, err
	}
	item, err := s.Library.ItemForTitle(ctx, caller.UserID, title.ID)
	if err != nil {
		return 0, err
	}
	if item == nil {
		status := core.StatusWishlist
		if _, err := s.Library.Add(ctx, core.MediaRef{TitleID: &title.ID, Type: title.Type}, &status, caller.UserID, library.AgentCaller(caller.Token)); err != nil {
			return 0, err
		}
	}
	return Accepted, nil
}
