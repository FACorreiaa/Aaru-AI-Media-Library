package imports

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"strconv"
	"strings"
)

// IMP-013 and IMP-014: anime lists from MyAnimeList (XML export) and AniList (public list by
// username), and their manga lists too (MNG-002; AnimeListImport). Both carry hard ids (`mal`,
// `anilist`), so rows resolve through AniList and the same show imported from both lands on one
// title. Episodes are season 1, as for every AniList entry.

// AnimeListStatus maps MAL and AniList statuses on Aaru's five (IMP-013). On hold (AniList: paused)
// is Aaru's on hold (LIB-007); rewatching is still in progress. MAL's manga list says reading and
// plan to read; its numeric codes are the anime list's.
func AnimeListStatus(value string) *core.LibraryStatus {
	switch strings.ReplaceAll(strings.ToLower(value), " ", "") {
	case "watching", "reading", "1", "current", "repeating", "rereading":
		return ptr(core.StatusInProgress)
	case "on-hold", "onhold", "3", "paused":
		return ptr(core.StatusOnHold)
	case "completed", "2":
		return ptr(core.StatusFinished)
	case "dropped", "4":
		return ptr(core.StatusDropped)
	case "plantowatch", "plantoread", "6", "planning":
		return ptr(core.StatusWishlist)
	}
	return nil
}

func isFinished(s *core.LibraryStatus) bool { return s != nil && *s == core.StatusFinished }

// animeRead is a manga's chapter or volume as read: a completed entry exported with 0 read means
// all of them, when the total is known. Zero is none.
func animeRead(count int, total *int, status *core.LibraryStatus) *int {
	read := count
	if isFinished(status) && count == 0 {
		read = 0
		if total != nil {
			read = *total
		}
	}
	if read > 0 {
		return &read
	}
	return nil
}

// animeWatched is episodes 1…n of season 1, the AniList shape.
func animeWatched(count int) []core.EpisodeKey {
	if count <= 0 {
		return nil
	}
	keys := make([]core.EpisodeKey, 0, count)
	for e := 1; e <= count; e++ {
		if key, err := core.NewEpisodeKey(1, e); err == nil {
			keys = append(keys, key)
		}
	}
	return keys
}

// animeRating is a score on Aaru's 1–10 scale; 0 (MAL and AniList's "no score") is none.
func animeRating(score *float64) *float64 {
	if score == nil || *score < 1 || *score > 10 {
		return nil
	}
	return score
}

// animeProgress: a completed entry exported with 0 progress means every episode.
func animeProgress(watched int, total *int, status *core.LibraryStatus, isMovie bool) []core.EpisodeKey {
	if isMovie {
		return nil
	}
	if isFinished(status) && watched == 0 {
		watched = 0
		if total != nil {
			watched = *total
		}
	}
	return animeWatched(watched)
}

// MARK: MyAnimeList XML (IMP-013)

// ParseMALList reads MAL's export: flat XML, one `<anime>` (or `<manga>`) element per entry with
// simple child elements, some in CDATA. Read with a small scanner, as Swift did.
func ParseMALList(text string) ([]Row, error) {
	if !strings.Contains(text, "<myanimelist") ||
		(!strings.Contains(text, "<anime>") && !strings.Contains(text, "<manga>") && !strings.Contains(text, "</myinfo>")) {
		return nil, formatError("This does not look like a MyAnimeList export. Export your anime or manga list from " +
			"MAL and upload the .xml (or .xml.gz) file.")
	}
	return append(malAnimeRows(text), malMangaRows(text)...), nil
}

// malMangaRows is MAL's manga export (MNG-002): `<manga>` entries with their own MAL ids, read
// chapters and volumes.
func malMangaRows(text string) []Row {
	var rows []Row
	for _, block := range malBlocks("manga", text) {
		id := malField("manga_mangadb_id", block)
		title := malField("manga_title", block)
		if id == nil || optInt(id) == nil || title == nil {
			continue
		}
		status := optStatus(malField("my_status", block))
		count := func(name string) *int { return optInt(malField(name, block)) }
		rows = append(rows, Row{
			SourceKey: ptr("mal-manga:" + *id), Type: core.MediaManga, Title: *title,
			IDs: core.ExternalIDs{MAL: *id}, Status: status,
			Rating:       animeRating(optDouble(malField("my_score", block))),
			FinishedAt:   catalog.ParseDay(malField("my_finish_date", block)),
			Lists:        []string{},
			MangaChapter: animeRead(deref(count("my_read_chapters")), count("manga_chapters"), status),
			MangaVolume:  animeRead(deref(count("my_read_volumes")), count("manga_volumes"), status),
			KnowsOnHold:  ptr(true),
		})
	}
	return rows
}

func malAnimeRows(text string) []Row {
	var rows []Row
	for _, block := range malBlocks("anime", text) {
		id := malField("series_animedb_id", block)
		title := malField("series_title", block)
		if id == nil || optInt(id) == nil || title == nil {
			continue
		}
		seriesType := malField("series_type", block)
		isMovie := seriesType != nil && strings.ToLower(*seriesType) == "movie"
		status := optStatus(malField("my_status", block))
		mediaType := core.MediaShow
		if isMovie {
			mediaType = core.MediaMovie
		}
		rows = append(rows, Row{
			SourceKey: ptr("mal:" + *id), Type: mediaType, Title: *title,
			IDs: core.ExternalIDs{MAL: *id}, Status: status,
			Rating:     animeRating(optDouble(malField("my_score", block))),
			FinishedAt: catalog.ParseDay(malField("my_finish_date", block)),
			Lists:      []string{},
			Watched: animeProgress(deref(optInt(malField("my_watched_episodes", block))),
				optInt(malField("series_episodes", block)), status, isMovie),
			KnowsOnHold: ptr(true),
		})
	}
	return rows
}

func optStatus(s *string) *core.LibraryStatus {
	if s == nil {
		return nil
	}
	return AnimeListStatus(*s)
}

// malBlocks is the contents of every `<name>…</name>` element, in order.
func malBlocks(name, text string) []string {
	open, closeTag := "<"+name+">", "</"+name+">"
	var found []string
	rest := text
	for {
		o := strings.Index(rest, open)
		if o < 0 {
			return found
		}
		after := rest[o+len(open):]
		c := strings.Index(after, closeTag)
		if c < 0 {
			return found
		}
		found = append(found, after[:c])
		rest = after[c+len(closeTag):]
	}
}

// malField is one child element's text: CDATA unwrapped, entities decoded, blank and MAL's empty
// `0000-00-00` dates treated as absent.
func malField(name, block string) *string {
	values := malBlocks(name, block)
	if len(values) == 0 {
		return nil
	}
	text := trimWSNL(values[0])
	if strings.HasPrefix(text, "<![CDATA[") && strings.HasSuffix(text, "]]>") && len(text) >= len("<![CDATA[]]>") {
		text = text[len("<![CDATA[") : len(text)-len("]]>")]
	} else {
		text = malDecodeEntities(text)
	}
	text = trimWSNL(text)
	if text == "" || text == "0000-00-00" {
		return nil
	}
	return &text
}

func malDecodeEntities(text string) string {
	if !strings.Contains(text, "&") {
		return text
	}
	for _, e := range [][2]string{{"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&apos;", "'"}, {"&#039;", "'"}} {
		text = strings.ReplaceAll(text, e[0], e[1])
	}
	return strings.ReplaceAll(text, "&amp;", "&")
}

// MARK: AniList (IMP-014)

// AniListRows reads a public AniList list by username as import rows (AniListCatalog+Lists).
type AniListRows struct {
	AniList *catalog.AniList
}

// ListRows is the anime list, then the manga list (MNG-002). A private list or unknown user is a
// provider KindNotFound.
func (a AniListRows) ListRows(ctx context.Context, userName string) ([]Row, error) {
	entries, err := a.AniList.ListEntries(ctx, userName)
	if err != nil {
		return nil, err
	}
	rows := make([]Row, 0, len(entries))
	for _, e := range entries {
		rows = append(rows, AniListEntryRow(e))
	}
	return rows, nil
}

// AniListEntryRow is one list entry as an import row. AniList's `progress` on a manga is chapters;
// `progressVolumes` is volumes.
func AniListEntryRow(e catalog.AniListListEntry) Row {
	status := AnimeListStatus(e.Status)
	ids := core.ExternalIDs{AniList: strconv.Itoa(e.MediaID)}
	if e.MediaIDMal != nil {
		ids.MAL = strconv.Itoa(*e.MediaIDMal)
	}
	row := Row{
		SourceKey: ptr("anilist:" + strconv.Itoa(e.MediaID)), Title: e.Title, Year: e.Year, IDs: ids,
		Status: status, Rating: animeRating(e.Score), FinishedAt: e.CompletedAt, Lists: []string{},
		KnowsOnHold: ptr(true),
	}
	if e.Type == core.MediaManga {
		row.Type = core.MediaManga
		row.MangaChapter = animeRead(deref(e.Progress), e.Chapters, status)
		row.MangaVolume = animeRead(deref(e.ProgressVolumes), e.Volumes, status)
		return row
	}
	isMovie := e.Format != nil && *e.Format == "MOVIE"
	row.Type = core.MediaShow
	if isMovie {
		row.Type = core.MediaMovie
	}
	row.Watched = animeProgress(deref(e.Progress), e.Episodes, status, isMovie)
	return row
}
