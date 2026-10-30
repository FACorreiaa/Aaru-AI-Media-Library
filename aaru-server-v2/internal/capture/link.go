package capture

import (
	"aaru-go-api/internal/core"
	"net/url"
	"strings"
)

// LinkKind is what a link sent as a capture is (CaptureLink).
type LinkKind int

// The kinds of link.
const (
	// LinkUnsupported is any other link.
	LinkUnsupported LinkKind = iota
	// LinkTitle is TMDB, AniList or Open Library: the title the URL names.
	LinkTitle
	// LinkUseCSV is Letterboxd or IMDb: their CSV export carries the whole list; Aaru does not
	// read their pages.
	LinkUseCSV
)

// Link is a parsed link. Aaru never fetches it: a catalog link names its title by id in the URL
// itself, and a site with an export is pointed at its CSV importer.
type Link struct {
	Kind LinkKind
	// Title is set for LinkTitle.
	Title *Title
	// Site is set for LinkUseCSV: "Letterboxd" or "IMDb".
	Site string
}

// ParseLink reads a link. raw is the URL as sent, already trimmed.
func ParseLink(raw string) Link {
	u, err := url.Parse(raw)
	if err != nil {
		return Link{}
	}
	scheme := strings.ToLower(u.Scheme)
	if (scheme != "https" && scheme != "http") || u.Hostname() == "" {
		return Link{}
	}
	host := strings.ToLower(u.Hostname())
	for _, prefix := range []string{"www.", "m."} {
		host = strings.TrimPrefix(host, prefix)
	}
	switch host {
	case "letterboxd.com", "boxd.it":
		return Link{Kind: LinkUseCSV, Site: "Letterboxd"}
	case "imdb.com":
		return Link{Kind: LinkUseCSV, Site: "IMDb"}
	}
	if t := catalogTitle(host, u, raw); t != nil {
		return Link{Kind: LinkTitle, Title: t}
	}
	return Link{}
}

// catalogTitle reads /movie/603-the-matrix and /tv/1396 on TMDB, /anime/21/One-Piece and
// /manga/30013/One-Piece on AniList (MNG-001), /works/OL45804W/Fantastic_Mr_Fox on Open Library.
func catalogTitle(host string, u *url.URL, raw string) *Title {
	var parts []string
	for _, p := range strings.Split(u.Path, "/") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) < 2 {
		return nil
	}
	id := parts[1]
	byNumber := func(mediaType core.MediaType, ids func(string) core.ExternalIDs) *Title {
		n := leadingNumber(id)
		if n == "" {
			return nil
		}
		return linkTitle(mediaType, ids(n), u, raw)
	}
	switch {
	case host == "themoviedb.org" && parts[0] == "movie":
		return byNumber(core.MediaMovie, func(n string) core.ExternalIDs { return core.ExternalIDs{TMDB: n} })
	case host == "themoviedb.org" && parts[0] == "tv":
		return byNumber(core.MediaShow, func(n string) core.ExternalIDs { return core.ExternalIDs{TMDB: n} })
	case host == "anilist.co" && parts[0] == "anime":
		return byNumber(core.MediaShow, func(n string) core.ExternalIDs { return core.ExternalIDs{AniList: n} })
	case host == "anilist.co" && parts[0] == "manga":
		return byNumber(core.MediaManga, func(n string) core.ExternalIDs { return core.ExternalIDs{AniList: n} })
	case host == "openlibrary.org" && parts[0] == "works" && strings.HasPrefix(id, "OL") && strings.HasSuffix(id, "W"):
		return linkTitle(core.MediaBook, core.ExternalIDs{OpenLibrary: id}, u, raw)
	}
	return nil
}

func leadingNumber(segment string) string {
	end := 0
	for end < len(segment) && segment[end] >= '0' && segment[end] <= '9' {
		end++
	}
	return segment[:end]
}

// linkTitle is the title a link becomes. Matched by its id; the link stands in for a name until
// then: host and path, as Foundation's URL.path gave it (no trailing slash).
func linkTitle(mediaType core.MediaType, ids core.ExternalIDs, u *url.URL, raw string) *Title {
	path := u.Path
	if len(path) > 1 {
		path = strings.TrimSuffix(path, "/")
	}
	key := raw
	return &Title{SourceKey: &key, Type: mediaType, Title: u.Hostname() + path, IDs: ids}
}
