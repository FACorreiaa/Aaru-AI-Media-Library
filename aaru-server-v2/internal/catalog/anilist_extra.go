package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"regexp"
	"strings"
	"time"
)

// MARK: Discover (DISC-001)

// DiscoverLists are the rows AniList serves.
func (a *AniList) DiscoverLists() []DiscoverList {
	return []DiscoverList{ListAnimeSeason, ListAnimeTrending, ListMangaTrending, ListMangaPublishing}
}

// List fetches one anime or manga row. No adult works.
func (a *AniList) List(ctx context.Context, list DiscoverList, now time.Time) ([]Hit, error) {
	if list.Kind() == RowManga {
		// DISC-004: what is trending, and the most popular series still publishing.
		sort := "POPULARITY_DESC"
		if list == ListMangaTrending {
			sort = "TRENDING_DESC"
		}
		var body aniListSearchData
		err := a.post(ctx, fmt.Sprintf(`query {
  Page(perPage: 20) {
    media(type: MANGA, isAdult: false, status: RELEASING, sort: %s) {
      %s
    }
  }
}`, sort, aniListFields(core.MediaManga)), nil, &body)
		if err != nil {
			return nil, err
		}
		return body.hits(), nil
	}
	var filter string
	switch list {
	case ListAnimeSeason:
		current := CurrentSeason(now)
		filter = fmt.Sprintf("season: %s, seasonYear: %d, sort: POPULARITY_DESC", current.Season.AniList(), current.Year)
	case ListAnimeTrending:
		filter = "status: RELEASING, sort: TRENDING_DESC"
	default:
		return nil, provider.NewError("anilist", provider.KindNotFound)
	}
	var body aniListSearchData
	err := a.post(ctx, fmt.Sprintf(`query {
  Page(perPage: 20) {
    media(type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, ONA, MOVIE], %s) {
      %s
    }
  }
}`, filter, aniListMediaFields), nil, &body)
	if err != nil {
		return nil, err
	}
	return body.hits(), nil
}

// MARK: Seasons (DISC-002)

// AniListSeasonPageSize is anime per season page.
const AniListSeasonPageSize = 50

// SeasonKinds are the Seasons lists AniList serves.
func (a *AniList) SeasonKinds() []SeasonKind { return []SeasonKind{SeasonAnime} }

// Season is one page of a season's anime.
func (a *AniList) Season(ctx context.Context, key SeasonKey, kind SeasonKind, page int, _ time.Time) (SeasonPage, error) {
	if kind != SeasonAnime {
		return SeasonPage{}, provider.NewError("anilist", provider.KindNotFound)
	}
	var body struct {
		Page struct {
			PageInfo *struct {
				HasNextPage *bool `json:"hasNextPage"`
				Total       *int  `json:"total"`
			} `json:"pageInfo"`
			Media []aniListMedia `json:"media"`
		} `json:"Page"`
	}
	err := a.post(ctx, fmt.Sprintf(`query ($season: MediaSeason, $year: Int, $page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage total }
    media(season: $season, seasonYear: $year, type: ANIME, isAdult: false,
          format_in: [TV, TV_SHORT, ONA, MOVIE], sort: POPULARITY_DESC) {
      %s
    }
  }
}`, aniListMediaFields), map[string]any{
		"season": key.Season.AniList(), "year": key.Year, "page": page, "perPage": AniListSeasonPageSize,
	}, &body)
	if err != nil {
		return SeasonPage{}, err
	}
	hits := make([]Hit, 0, len(body.Page.Media))
	for _, m := range body.Page.Media {
		hits = append(hits, m.hit())
	}
	result := SeasonPage{Hits: hits}
	if info := body.Page.PageInfo; info != nil {
		result.HasMore = info.HasNextPage != nil && *info.HasNextPage
		result.Total = info.Total
	}
	return result, nil
}

// MARK: Lists (IMP-014)

// AniListListEntry is one entry of a user's public AniList list, as AniList gives
// it. The imports area maps it to an import row (status, rating and progress rules
// live there, in AnimeListImport).
type AniListListEntry struct {
	// Type is MediaShow for the anime list and MediaManga for the manga list.
	Type core.MediaType
	// Status is AniList's (CURRENT, COMPLETED, PAUSED, DROPPED, PLANNING, REPEATING).
	Status string
	// Progress is episodes for anime, chapters for manga.
	Progress        *int
	ProgressVolumes *int
	// Score is on AniList's POINT_10_DECIMAL scale.
	Score *float64
	// CompletedAt is the completion day at 00:00 UTC, when AniList has the full date.
	CompletedAt *time.Time
	MediaID     int
	MediaIDMal  *int
	Format      *string
	Episodes    *int
	Chapters    *int
	Volumes     *int
	// Title is the English title, else romaji, else "Untitled".
	Title string
	Year  *int
}

// ListEntries reads the user's anime list, then the manga list (MNG-002). A user
// with only one of them is fine. A private list or unknown user is a provider
// KindNotFound.
func (a *AniList) ListEntries(ctx context.Context, userName string) ([]AniListListEntry, error) {
	anime, err := a.listEntries(ctx, userName, core.MediaShow)
	if err != nil {
		return nil, err
	}
	manga, err := a.listEntries(ctx, userName, core.MediaManga)
	if err != nil {
		return nil, err
	}
	return append(anime, manga...), nil
}

func (a *AniList) listEntries(ctx context.Context, userName string, mediaType core.MediaType) ([]AniListListEntry, error) {
	type fuzzy struct {
		Year, Month, Day *int
	}
	var body struct {
		Collection struct {
			Lists []struct {
				Entries []struct {
					Status          string   `json:"status"`
					Progress        *int     `json:"progress"`
					ProgressVolumes *int     `json:"progressVolumes"`
					Score           *float64 `json:"score"`
					CompletedAt     *fuzzy   `json:"completedAt"`
					Media           struct {
						ID       int     `json:"id"`
						IDMal    *int    `json:"idMal"`
						Format   *string `json:"format"`
						Episodes *int    `json:"episodes"`
						Chapters *int    `json:"chapters"`
						Volumes  *int    `json:"volumes"`
						Title    struct {
							Romaji  *string `json:"romaji"`
							English *string `json:"english"`
						} `json:"title"`
						StartDate *struct {
							Year *int `json:"year"`
						} `json:"startDate"`
					} `json:"media"`
				} `json:"entries"`
			} `json:"lists"`
		} `json:"MediaListCollection"`
	}
	err := a.post(ctx, fmt.Sprintf(`query ($name: String) {
  MediaListCollection(userName: $name, type: %s) {
    lists { entries {
      status progress progressVolumes score(format: POINT_10_DECIMAL)
      completedAt { year month day }
      media { id idMal format episodes chapters volumes title { romaji english } startDate { year } }
    } }
  }
}`, aniListType(mediaType)), map[string]any{"name": userName}, &body)
	if err != nil {
		return nil, err
	}
	var out []AniListListEntry
	for _, list := range body.Collection.Lists {
		for _, e := range list.Entries {
			title := "Untitled"
			if e.Media.Title.English != nil {
				title = *e.Media.Title.English
			} else if e.Media.Title.Romaji != nil {
				title = *e.Media.Title.Romaji
			}
			entry := AniListListEntry{
				Type: mediaType, Status: e.Status, Progress: e.Progress, ProgressVolumes: e.ProgressVolumes,
				Score: e.Score, MediaID: e.Media.ID, MediaIDMal: e.Media.IDMal, Format: e.Media.Format,
				Episodes: e.Media.Episodes, Chapters: e.Media.Chapters, Volumes: e.Media.Volumes, Title: title,
			}
			if e.Media.StartDate != nil {
				entry.Year = e.Media.StartDate.Year
			}
			if c := e.CompletedAt; c != nil && c.Year != nil && c.Month != nil && c.Day != nil {
				entry.CompletedAt = ParseDay(strPtr(fmt.Sprintf("%04d-%02d-%02d", *c.Year, *c.Month, *c.Day)))
			}
			out = append(out, entry)
		}
	}
	return out, nil
}

// MARK: Text

var (
	htmlBreak       = regexp.MustCompile(`(?i)<br\s*/?>`)
	htmlTag         = regexp.MustCompile(`<[^>]+>`)
	trailingSpaceNL = regexp.MustCompile("[ \t]+\n")
	manyNewlines    = regexp.MustCompile(`\n{3,}`)
)

// AniListPlainText notes: AniList sends `<br>` and `<i>` even with `asHtml: false`. Clients get plain text.
func AniListPlainText(html string) string {
	text := htmlBreak.ReplaceAllString(html, "\n")
	text = htmlTag.ReplaceAllString(text, "")
	// `&amp;` last, or "&amp;lt;" (a literal "&lt;") would decode twice to "<".
	for _, e := range [][2]string{
		{"&quot;", `"`}, {"&#039;", "'"}, {"&#39;", "'"}, {"&lt;", "<"}, {"&gt;", ">"}, {"&nbsp;", " "}, {"&amp;", "&"},
	} {
		text = strings.ReplaceAll(text, e[0], e[1])
	}
	text = trailingSpaceNL.ReplaceAllString(text, "\n")
	text = manyNewlines.ReplaceAllString(text, "\n\n")
	return strings.TrimSpace(text)
}
