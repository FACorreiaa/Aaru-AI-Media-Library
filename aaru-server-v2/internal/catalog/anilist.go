package catalog

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

// AniListEndpoint is AniList's GraphQL endpoint.
const AniListEndpoint = "https://graphql.anilist.co"

// AniListBatchSize is AniList's largest page.
const AniListBatchSize = 50

const aniListMediaFields = `id idMal type format status episodes duration chapters volumes genres
title { romaji english native }
startDate { year month day }
coverImage { large }
bannerImage
externalLinks { site type }
description(asHtml: false)`

// aniListStaffFields are a manga's credits: the people who wrote and drew it become its byline.
const aniListStaffFields = "staff(perPage: 6, sort: [RELEVANCE, ROLE]) { edges { role node { name { full } } } }"

// AniList is the AniList adapter (CAT-007): the anime and manga catalog (MNG-001),
// over GraphQL. Reads need no key. Each AniList anime entry is one season/cour, so
// its episodes are season 1. Also Discover's anime and manga rows, the anime
// Seasons list, and public list reading for imports (IMP-014).
type AniList struct {
	Client *provider.Client
	// UserAgent identifies Aaru; the same contact string as Open Library.
	UserAgent string
	// Endpoint defaults to AniListEndpoint; tests point it at a stub server.
	Endpoint string
}

// aniListType is AniList's own split: everything Aaru calls manga is MANGA, the rest ANIME.
func aniListType(mediaType core.MediaType) string {
	if mediaType == core.MediaManga {
		return "MANGA"
	}
	return "ANIME"
}

// aniListFields are the fields for one kind: manga also asks for its credits.
func aniListFields(mediaType core.MediaType) string {
	if mediaType == core.MediaManga {
		return aniListMediaFields + " " + aniListStaffFields
	}
	return aniListMediaFields
}

// Search finds anime (any type but manga) or manga.
func (a *AniList) Search(ctx context.Context, query string, mediaType core.MediaType) ([]Hit, error) {
	// Manga search hides adult works, as Discover does for anime.
	adult := ""
	if mediaType == core.MediaManga {
		adult = ", isAdult: false"
	}
	var body aniListSearchData
	err := a.post(ctx, fmt.Sprintf(`query ($search: String) {
  Page(perPage: 20) {
    media(search: $search, type: %s%s, sort: SEARCH_MATCH) {
      %s
    }
  }
}`, aniListType(mediaType), adult, aniListFields(mediaType)), map[string]any{"search": query}, &body)
	if err != nil {
		return nil, err
	}
	return body.hits(), nil
}

// Hydrate is the record for an AniList or MAL id.
func (a *AniList) Hydrate(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*Record, error) {
	media, err := a.media(ctx, ids, mediaType, false)
	if err != nil || media == nil {
		return nil, err
	}
	hit := media.hit()
	hit.IDs = hit.IDs.Filling(ids)
	return media.record(hit), nil
}

// HydrateMAL is IMP-017: many MyAnimeList entries at once, 50 per request, keyed by
// MAL id. An id AniList does not know is simply missing from the result.
func (a *AniList) HydrateMAL(ctx context.Context, malIDs []string, mediaType core.MediaType) (map[string]Record, error) {
	seen := map[int]bool{}
	var ids []int
	for _, s := range malIDs {
		if n, err := strconv.Atoi(s); err == nil && !seen[n] {
			seen[n] = true
			ids = append(ids, n)
		}
	}
	slices.Sort(ids)
	titles := map[string]Record{}
	for start := 0; start < len(ids); start += AniListBatchSize {
		batch := ids[start:min(start+AniListBatchSize, len(ids))]
		var body aniListSearchData
		err := a.post(ctx, fmt.Sprintf(`query ($ids: [Int]) {
  Page(perPage: %d) {
    media(idMal_in: $ids, type: %s) { %s }
  }
}`, AniListBatchSize, aniListType(mediaType), aniListFields(mediaType)), map[string]any{"ids": batch}, &body)
		if err != nil {
			return nil, err
		}
		for _, m := range body.Page.Media {
			if m.IDMal == nil {
				continue
			}
			titles[strconv.Itoa(*m.IDMal)] = *m.record(m.hit())
		}
	}
	return titles, nil
}

// Episodes are the anime's episodes as season 1, timed by its airing schedule.
func (a *AniList) Episodes(ctx context.Context, ids core.ExternalIDs) (*Episodes, error) {
	media, err := a.media(ctx, ids, core.MediaShow, true)
	if err != nil || media == nil {
		return nil, err
	}
	airsAt := map[int]time.Time{}
	if media.AiringSchedule != nil {
		for _, n := range media.AiringSchedule.Nodes {
			if _, ok := airsAt[n.Episode]; !ok {
				airsAt[n.Episode] = time.Unix(n.AiringAt, 0).UTC()
			}
		}
	}
	if next := media.NextAiringEpisode; next != nil {
		airsAt[next.Episode] = time.Unix(next.AiringAt, 0).UTC()
	}
	// Known episode count, or as far as the schedule reaches for a show still airing.
	count := 0
	if media.Episodes != nil {
		count = *media.Episodes
	}
	for n := range airsAt {
		count = max(count, n)
	}
	if count <= 0 {
		return &Episodes{Status: media.titleStatus(), Episodes: []Episode{}}, nil
	}
	names := AniListEpisodeNames(media.StreamingEpisodes, count)
	episodes := make([]Episode, 0, count)
	for n := 1; n <= count; n++ {
		e := Episode{Season: 1, Episode: n, RuntimeMinutes: media.Duration}
		if name, ok := names[n]; ok {
			e.Name = &name
		}
		if at, ok := airsAt[n]; ok {
			e.AirsAt, e.AirTimeKnown = &at, true
		}
		episodes = append(episodes, e)
	}
	return &Episodes{Status: media.titleStatus(), Episodes: episodes, BackdropURL: media.backdropURL(), Network: media.network()}, nil
}

var aniListEpisodeTitle = regexp.MustCompile(`(?i)^episode\s+(\d+)\s*[-–:]\s*(.+)$`)

// AniListEpisodeNames notes: AniList has no per-episode titles, but its streaming links are
// titled "Episode 3 - Name". Only names are kept, and only when the number is inside
// the show's range; anything else is left unnamed, never guessed.
func AniListEpisodeNames(links []AniListStreamingEpisode, count int) map[int]string {
	names := map[int]string{}
	for _, link := range links {
		if link.Title == nil {
			continue
		}
		m := aniListEpisodeTitle.FindStringSubmatch(*link.Title)
		if m == nil {
			continue
		}
		n, err := strconv.Atoi(m[1])
		if err != nil || n < 1 || n > count {
			continue
		}
		if _, taken := names[n]; taken {
			continue
		}
		if name := strings.Trim(m[2], " \t"); name != "" {
			names[n] = name
		}
	}
	return names
}

func (a *AniList) media(ctx context.Context, ids core.ExternalIDs, mediaType core.MediaType, withSchedule bool) (*aniListMedia, error) {
	schedule := ""
	if withSchedule {
		schedule = `airingSchedule(notYetAired: false, perPage: 50) { nodes { episode airingAt } }
nextAiringEpisode { episode airingAt }
streamingEpisodes { title }`
	}
	var selector string
	var id int
	if n, err := strconv.Atoi(ids.AniList); ids.AniList != "" && err == nil {
		selector, id = "id: $id", n
	} else if n, err := strconv.Atoi(ids.MAL); ids.MAL != "" && err == nil {
		selector, id = "idMal: $id", n
	} else {
		return nil, nil //nolint:nilnil // nil: the provider does not know these ids
	}
	var body struct {
		Media *aniListMedia `json:"Media"`
	}
	err := a.post(ctx, fmt.Sprintf(`query ($id: Int) {
  Media(%s, type: %s) { %s %s }
}`, selector, aniListType(mediaType), aniListFields(mediaType), schedule), map[string]any{"id": id}, &body)
	if provider.IsNotFound(err) {
		return nil, nil //nolint:nilnil // nil: the provider does not know these ids
	}
	if err != nil {
		return nil, err
	}
	return body.Media, nil
}

// post sends one GraphQL query; a response without data is KindNotFound.
func (a *AniList) post(ctx context.Context, query string, variables map[string]any, v any) error {
	if variables == nil {
		variables = map[string]any{}
	}
	payload, err := json.Marshal(map[string]any{"query": query, "variables": variables})
	if err != nil {
		return fmt.Errorf("encode graphql: %w", err)
	}
	userAgent := cmp.Or(a.UserAgent, config.DefaultProviderUserAgent)
	var response struct {
		Data json.RawMessage `json:"data"`
	}
	err = a.Client.DecodeJSON(ctx, provider.Request{
		Method: "POST", URL: cmp.Or(a.Endpoint, AniListEndpoint), Body: payload,
		Headers: [][2]string{{"Content-Type", "application/json"}, {"Accept", "application/json"}, {"User-Agent", userAgent}},
	}, &response)
	if err != nil {
		return err
	}
	if len(response.Data) == 0 || string(response.Data) == "null" {
		return provider.NewError("anilist", provider.KindNotFound)
	}
	if err := json.Unmarshal(response.Data, v); err != nil {
		return provider.NewError(a.Client.Name, provider.KindMalformed)
	}
	return nil
}

// ClassifyAniList reads AniList's own outage answers: a 401/403 saying the API is
// disabled, or a non-JSON page from the CDN in front of it. Reads need no key, so
// these are never a refused credential.
func ClassifyAniList(resp *provider.Response) (provider.ErrorKind, bool) {
	if resp.Status != 401 && resp.Status != 403 {
		return 0, false
	}
	var body struct {
		Errors []struct {
			Message *string `json:"message"`
		} `json:"errors"`
	}
	if err := json.Unmarshal(resp.Body, &body); err != nil {
		return provider.KindUnavailable, true
	}
	for _, e := range body.Errors {
		if e.Message != nil && strings.Contains(strings.ToLower(*e.Message), "disabled") {
			return provider.KindUnavailable, true
		}
	}
	return 0, false
}

// MARK: - AniList wire shapes

type aniListSearchData struct {
	Page struct {
		Media []aniListMedia `json:"media"`
	} `json:"Page"`
}

func (d aniListSearchData) hits() []Hit {
	hits := make([]Hit, 0, len(d.Page.Media))
	for _, m := range d.Page.Media {
		hits = append(hits, m.hit())
	}
	return hits
}

// AniListStreamingEpisode is one streaming link AniList lists for an episode.
type AniListStreamingEpisode struct {
	Title *string `json:"title"`
}

type aniListAiring struct {
	Episode  int   `json:"episode"`
	AiringAt int64 `json:"airingAt"`
}

type aniListMedia struct {
	ID    int  `json:"id"`
	IDMal *int `json:"idMal"`
	// Type is ANIME or MANGA.
	Type     *string `json:"type"`
	Format   *string `json:"format"`
	Status   *string `json:"status"`
	Episodes *int    `json:"episodes"`
	Duration *int    `json:"duration"`
	Chapters *int    `json:"chapters"`
	Volumes  *int    `json:"volumes"`
	Staff    *struct {
		Edges []struct {
			Role *string `json:"role"`
			Node struct {
				Name struct {
					Full *string `json:"full"`
				} `json:"name"`
			} `json:"node"`
		} `json:"edges"`
	} `json:"staff"`
	Genres []string `json:"genres"`
	Title  struct {
		Romaji  *string `json:"romaji"`
		English *string `json:"english"`
		Native  *string `json:"native"`
	} `json:"title"`
	StartDate *struct {
		Year  *int `json:"year"`
		Month *int `json:"month"`
		Day   *int `json:"day"`
	} `json:"startDate"`
	CoverImage *struct {
		Large *string `json:"large"`
	} `json:"coverImage"`
	BannerImage   *string `json:"bannerImage"`
	ExternalLinks []struct {
		Site string  `json:"site"`
		Type *string `json:"type"`
	} `json:"externalLinks"`
	Description    *string `json:"description"`
	AiringSchedule *struct {
		Nodes []aniListAiring `json:"nodes"`
	} `json:"airingSchedule"`
	NextAiringEpisode *aniListAiring            `json:"nextAiringEpisode"`
	StreamingEpisodes []AniListStreamingEpisode `json:"streamingEpisodes"`
}

func (m aniListMedia) isManga() bool { return sval(m.Type) == "MANGA" }

func (m aniListMedia) record(hit Hit) *Record {
	genres := m.Genres
	if genres == nil {
		genres = []string{}
	}
	return &Record{Hit: hit, Status: m.titleStatus(), RuntimeMinutes: m.Duration, Genres: genres}
}

func positive(p *int) *int {
	if p == nil || *p <= 0 {
		return nil
	}
	return p
}

func (m aniListMedia) hit() Hit {
	display := "Untitled"
	for _, t := range []*string{m.Title.English, m.Title.Romaji, m.Title.Native} {
		if t != nil {
			display = *t
			break
		}
	}
	mediaType := core.MediaShow
	switch {
	case m.isManga():
		mediaType = core.MediaManga
	case sval(m.Format) == "MOVIE":
		mediaType = core.MediaMovie
	}
	var original *string
	if m.Title.Native != nil && *m.Title.Native != display {
		original = m.Title.Native
	}
	var year *int
	var release *string
	if m.StartDate != nil {
		year = m.StartDate.Year
		if m.StartDate.Year != nil && m.StartDate.Month != nil && m.StartDate.Day != nil {
			release = strPtr(fmt.Sprintf("%04d-%02d-%02d", *m.StartDate.Year, *m.StartDate.Month, *m.StartDate.Day))
		}
	}
	var poster *string
	if m.CoverImage != nil {
		poster = m.CoverImage.Large
	}
	var overview *string
	if m.Description != nil {
		overview = blankToNil(AniListPlainText(*m.Description))
	}
	ids := core.ExternalIDs{AniList: strconv.Itoa(m.ID)}
	if m.IDMal != nil {
		ids.MAL = strconv.Itoa(*m.IDMal)
	}
	hit := Hit{
		Type: mediaType, Title: display, OriginalTitle: original, Year: year, PosterURL: poster,
		Overview: overview, IDs: ids, IsAnime: !m.isManga(), BackdropURL: m.backdropURL(), ReleaseDate: release,
	}
	if m.isManga() {
		hit.Byline = m.authors()
		hit.ChapterCount = positive(m.Chapters)
		hit.VolumeCount = positive(m.Volumes)
	} else {
		hit.Network = m.network()
	}
	return hit
}

// storyOrArt is Swift's `(?i)\b(story|art)\b`; core.MatchWordBounded checks the boundaries as ICU does.
var storyOrArt = regexp.MustCompile(`(?i)(story|art)`)

// authors are who wrote and drew it ("Story & Art", "Story", "Art", "Original Story"),
// in AniList's order, once each, at most two. Translators, letterers and editors are left out.
func (m aniListMedia) authors() *string {
	if m.Staff == nil {
		return nil
	}
	var names []string
	for _, e := range m.Staff.Edges {
		if e.Role == nil || !core.MatchWordBounded(storyOrArt, *e.Role) {
			continue
		}
		name := nilIfBlank(e.Node.Name.Full)
		if name == nil || slices.Contains(names, *name) {
			continue
		}
		names = append(names, *name)
	}
	if len(names) == 0 {
		return nil
	}
	return strPtr(strings.Join(names[:min(2, len(names))], ", "))
}

func (m aniListMedia) backdropURL() *string { return m.BannerImage }

// network: anime has no broadcaster in AniList's model; the first streaming link is
// what a viewer needs ("Crunchyroll").
func (m aniListMedia) network() *string {
	for _, l := range m.ExternalLinks {
		if sval(l.Type) == "STREAMING" {
			return blankToNil(l.Site)
		}
	}
	return nil
}

func (m aniListMedia) titleStatus() *TitleStatus {
	var s TitleStatus
	switch sval(m.Status) {
	case "RELEASING", "HIATUS":
		s = StatusReturning
	case "NOT_YET_RELEASED":
		s = StatusUpcoming
	case "FINISHED":
		s = StatusEnded
	case "CANCELLED":
		s = StatusCanceled
	default:
		return nil
	}
	return &s
}
