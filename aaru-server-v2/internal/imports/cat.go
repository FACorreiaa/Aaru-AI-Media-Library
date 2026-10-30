package imports

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/google/uuid"
)

// IMP-009 and IMP-010: Pogdesign CAT (The TV Calendar, CATImport). CAT has no list export, so it
// comes in as a pasted list of show names or the user's own iCal file (or its link, read once).
// Only shows come across: CAT's watched episodes are not in either, so every show is planned as
// `wishlist`. Names carry no ids and rarely a year, so rows are `nameOnly` and match only when
// exactly one show has the name.

const (
	// CATMaxLines is the most lines a show list may have.
	CATMaxLines      = 2000
	catMaxNameLength = 200
)

type catShow struct {
	name   string
	airing *Airing
}

// catRows is one row per distinct show, in first-seen order. A name may end in CAT's `(2026)`. The
// show's first known airing is kept to break a tie between same-name shows.
func catRows(shows []catShow) []Row {
	index := map[string]int{}
	var rows []Row
	for _, show := range shows {
		title, year := catSplitYear(show.name)
		yearKey := "-"
		if year != nil {
			yearKey = strconv.Itoa(*year)
		}
		key := core.NormalizeTitle(title) + ":" + yearKey
		if title == "" {
			continue
		}
		if seen, ok := index[key]; ok {
			if rows[seen].Airing == nil {
				rows[seen].Airing = show.airing
			}
			continue
		}
		index[key] = len(rows)
		row := Row{
			SourceKey: ptr("cat:" + show.name), Type: core.MediaShow, Title: title, Year: year,
			Status: ptr(core.StatusWishlist), Lists: []string{}, Airing: show.airing,
		}
		if year == nil {
			row.NameOnly = ptr(true)
		}
		rows = append(rows, row)
	}
	return rows
}

var catYear = regexp.MustCompile(`^(.+?)` + swiftSpace + `*\((\d{4})\)$`)

// catSplitYear: `Brothers (2026)` → ("Brothers", 2026). CAT tells remakes apart this way.
func catSplitYear(name string) (string, *int) {
	trimmed := trimWS(name)
	m := catYear.FindStringSubmatch(trimmed)
	if m == nil {
		return trimmed, nil
	}
	year, ok := swiftInt(m[2])
	if !ok || year < 1900 || year > 2100 {
		return trimmed, nil
	}
	return m[1], &year
}

func catUnsupported(text, reason string) Row {
	return Row{SourceKey: ptr("cat:" + text), Type: core.MediaShow, Title: text, Lists: []string{}, Unsupported: &reason}
}

// MARK: Pasted list (IMP-009)

// ParseCATList reads one show per line, as typed or copied from CAT's show pages. Bullets and
// numbering are dropped.
func ParseCATList(text string) ([]Row, error) {
	var lines []string
	for _, line := range splitFunc(text, isSwiftNewline) {
		if cleaned := catClean(line); cleaned != "" {
			lines = append(lines, cleaned)
		}
	}
	if len(lines) > CATMaxLines {
		return nil, formatError("That is more than " + strconv.Itoa(CATMaxLines) + " lines. Paste one show per line.")
	}
	var names []catShow
	var tooLong []Row
	for _, line := range lines {
		if charCount(line) > catMaxNameLength {
			tooLong = append(tooLong, catUnsupported(charPrefix(line, 80)+"…",
				"Too long to be a show name. Put one show on each line."))
		} else {
			names = append(names, catShow{name: line})
		}
	}
	return append(catRows(names), tooLong...), nil
}

var catBullet = regexp.MustCompile(`^(?:[-*•·]|\d{1,4}[.)])` + swiftSpace + `+`)

// catClean: `- Severance`, `• Severance`, `3. Severance`, `3) Severance` → `Severance`.
func catClean(line string) string {
	value := trimWS(line)
	if loc := catBullet.FindStringIndex(value); loc != nil {
		value = value[loc[1]:]
	}
	return trimWS(value)
}

// MARK: iCal (IMP-010)

// ParseCATCalendar reads the user's exported CAT calendar: one event per episode. Every event's
// `SUMMARY` names its show and episode; the events collapse to one row per show, keeping one
// episode and its `DTSTART` day. A summary with no readable show name is listed as unmatched, once.
func ParseCATCalendar(text string) ([]Row, error) {
	if !IsCATCalendar(text) {
		return nil, formatError("That is not a calendar file. Export the iCal file from CAT.")
	}
	var shows []catShow
	var unreadable []string
	var summary, day *string
	for _, line := range icsUnfolded(text) {
		upper := strings.ToUpper(line)
		switch {
		case upper == "BEGIN:VEVENT":
			summary, day = nil, nil
		case upper == "END:VEVENT" && summary != nil:
			if name, ok := CATShowName(*summary); ok {
				var airing *Airing
				if day != nil {
					if season, episode, ok := catEpisode(*summary); ok {
						airing = &Airing{Season: season, Episode: episode, Day: *day}
					}
				}
				shows = append(shows, catShow{name: name, airing: airing})
			} else if !containsString(unreadable, *summary) {
				unreadable = append(unreadable, *summary)
			}
		case upper == "END:VEVENT":
		default:
			if value, ok := icsValue("SUMMARY", line); ok {
				// The event's own comes first; a later one belongs to a nested alarm.
				if summary == nil {
					summary = &value
				}
			} else if value, ok := icsValue("DTSTART", line); ok {
				if day == nil {
					day = catCalendarDay(value)
				}
			}
		}
	}
	rows := catRows(shows)
	for _, s := range unreadable {
		rows = append(rows, catUnsupported(s, "Couldn't read a show name from “"+s+"”."))
	}
	return rows, nil
}

func containsString(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// IsCATCalendar is whether text is an iCalendar file (its first line, past whitespace and a BOM).
func IsCATCalendar(text string) bool {
	start := strings.TrimLeftFunc(text, func(r rune) bool { return unicode.IsSpace(r) || r == '\uFEFF' })
	return strings.HasPrefix(strings.ToUpper(charPrefix(start, 15)), "BEGIN:VCALENDAR")
}

// icsUnfolded: RFC 5545 §3.1, a line starting with a space or tab continues the previous one.
// Lines end in "\n" or "\r\n"; a "\r" left at a line's end is dropped too, as Swift did.
func icsUnfolded(text string) []string {
	pieces := strings.Split(text, "\n")
	var lines []string
	for i, raw := range pieces {
		if i < len(pieces)-1 {
			// "\r\n" is one Character in Swift and the separator.
			raw = strings.TrimSuffix(raw, "\r")
		}
		if raw == "" {
			continue
		}
		line := strings.TrimSuffix(raw, "\r")
		if line != "" && (line[0] == ' ' || line[0] == '\t') && len(lines) > 0 {
			lines[len(lines)-1] += line[1:]
		} else {
			lines = append(lines, line)
		}
	}
	return lines
}

// icsValue is the unescaped value of name (parameters allowed: `SUMMARY;LANGUAGE=en:…`); false
// when the line is another property.
func icsValue(name, line string) (string, bool) {
	colon := strings.IndexByte(line, ':')
	if colon < 0 {
		return "", false
	}
	property := ""
	for _, piece := range strings.Split(line[:colon], ";") {
		if piece != "" {
			property = piece
			break
		}
	}
	if strings.ToUpper(property) != name {
		return "", false
	}
	return trimWS(icsUnescaped(line[colon+1:])), true
}

// icsUnescaped undoes RFC 5545 §3.3.11 TEXT escapes; `\n` reads as a space.
func icsUnescaped(value string) string {
	var b strings.Builder
	escaping := false
	for _, c := range characters(value) {
		switch {
		case escaping:
			if c == "n" || c == "N" {
				b.WriteString(" ")
			} else {
				b.WriteString(c)
			}
			escaping = false
		case c == "\\":
			escaping = true
		default:
			b.WriteString(c)
		}
	}
	return b.String()
}

// catEpisodePart is Swift's `\b[Ss](\d{1,3})\s*[Ee](\d{1,4})\b|\b(\d{1,3})x(\d{1,4})\b`, its word
// boundaries checked by core.FindWordBounded as ICU does (Unicode letters are word characters).
var catEpisodePart = regexp.MustCompile(`[Ss](\d{1,3})` + swiftSpace + `*[Ee](\d{1,4})|(\d{1,3})x(\d{1,4})`)

// catEpisodeAt is where a summary's first `S02E03` or `2x03` starts, and its numbers.
func catEpisodeAt(summary string) (start, season, episode int, ok bool) {
	m := core.FindWordBounded(catEpisodePart, summary)
	if m == nil {
		return 0, 0, 0, false
	}
	group := func(i int) string {
		if m[2*i] < 0 {
			return ""
		}
		return summary[m[2*i]:m[2*i+1]]
	}
	s, e := group(1), group(2)
	if m[2] < 0 {
		s, e = group(3), group(4)
	}
	season, okS := swiftInt(s)
	episode, okE := swiftInt(e)
	if !okS || !okE {
		return 0, 0, 0, false
	}
	return m[0], season, episode, true
}

// CATShowName reads the show from a summary: `Severance: S02E03 - Who Is Alive?`, `Severance - 2x03`, `Severance S02E03` →
// `Severance`.
func CATShowName(summary string) (string, bool) {
	start, _, _, ok := catEpisodeAt(summary)
	if !ok {
		return "", false
	}
	name := strings.Trim(summary[:start], " \t:-–|")
	return name, name != ""
}

func catEpisode(summary string) (season, episode int, ok bool) {
	_, season, episode, ok = catEpisodeAt(summary)
	return season, episode, ok
}

var catDay = regexp.MustCompile(`^(\d{4})(\d{2})(\d{2})`)

// catCalendarDay: `20261026T000000`, `20261026T000000Z` or `20261026` → `2026-10-26`. The time is
// dropped: it is CAT's local broadcast time, matched against date-only catalog air dates with a
// day's slack.
func catCalendarDay(value string) *string {
	m := catDay.FindStringSubmatch(value)
	if m == nil {
		return nil
	}
	return ptr(m[1] + "-" + m[2] + "-" + m[3])
}

// MARK: The iCal link (IMP-010)

// CATFeed reads the user's CAT calendar by its link (IMP-010).
type CATFeed interface {
	Calendar(ctx context.Context, calendarURL string) (string, error)
}

// CATCalendarFeed reads the user's own CAT calendar from the link CAT gives them, once per import.
// This is the only request Aaru makes to pogdesign.co.uk: no other page is read. The link holds
// the user's CAT key, so it is never stored or logged; it lives in one request's local variables.
type CATCalendarFeed struct {
	Client *provider.Client
}

// NewCATCalendarFeed is the feed over its own paced client ("pogdesign", 1/s burst 3).
func NewCATCalendarFeed(transport provider.Transport) *CATCalendarFeed {
	return &CATCalendarFeed{Client: provider.NewClient("pogdesign", transport, provider.NewPacer(1, 3))}
}

var (
	catHosts = map[string]bool{"www.pogdesign.co.uk": true, "pogdesign.co.uk": true}
	catPath  = regexp.MustCompile(`^/cat/(?:download|generate)_ics/([A-Za-z0-9_-]{1,128})/?$`)
)

// CATCalendarURL is the calendar link, checked and pointed at `generate_ics` (CAT's `download_ics`
// answers as an attachment). Anything that is not a CAT calendar link is refused before a request
// is made.
func CATCalendarURL(raw string) (string, error) {
	const message = "Paste the iCal link from CAT: it starts with https://www.pogdesign.co.uk/cat/."
	refused := apperr.Validation("url", message)
	trimmed := trimWSNL(raw)
	if strings.ContainsFunc(trimmed, func(r rune) bool { return unicode.IsSpace(r) || r < 0x20 || r == 0x7f }) {
		return "", refused
	}
	u, err := url.Parse(trimmed)
	if err != nil || strings.ToLower(u.Scheme) != "https" || u.Opaque != "" || !catHosts[strings.ToLower(u.Hostname())] ||
		strings.Contains(u.Host, ":") || u.User != nil {
		return "", refused
	}
	m := catPath.FindStringSubmatch(u.Path)
	if m == nil {
		return "", refused
	}
	return "https://www.pogdesign.co.uk/cat/generate_ics/" + m[1], nil
}

// Calendar reads the calendar at a checked link.
func (f *CATCalendarFeed) Calendar(ctx context.Context, calendarURL string) (string, error) {
	notACalendar := apperr.Validation("url", "That link didn't return a CAT calendar. Copy the iCal link from CAT again.").
		WithDetails(map[string]string{"url": "Not a CAT calendar."})
	body, err := f.Client.Data(ctx, provider.Request{URL: calendarURL, Headers: [][2]string{{"Accept", "text/calendar"}}})
	if err != nil {
		if p, ok := provider.AsError(err); ok && (p.Kind == provider.KindNotFound || p.Kind == provider.KindUnauthorized) {
			return "", notACalendar
		}
		return "", err
	}
	if len(body) > MaxUploadBytes {
		return "", apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That calendar is larger than 5 MB.")
	}
	if !utf8.Valid(body) || !IsCATCalendar(string(body)) {
		return "", notACalendar
	}
	return string(body), nil
}

// MARK: Requests

// CreateCATImport queues a pasted CAT show list, or the CAT calendar file's text: a calendar is
// told apart by its first line.
func (s *Service) CreateCATImport(ctx context.Context, user uuid.UUID, text string) (core.ImportJob, error) {
	source := core.SourceCATList
	if IsCATCalendar(text) {
		source = core.SourceCATICS
	}
	return s.CreateCSVImport(ctx, user, source, nil, text)
}

// errCATUnavailable is a server with no CAT feed.
var errCATUnavailable = apperr.New(http.StatusServiceUnavailable, "cat_unavailable",
	"Importing from a CAT link is not available right now. Upload the iCal file instead.")

// CreateCATFeedImport reads the calendar from the user's CAT link now (one bounded request, like
// reading an upload) and queues the matching. The link is not kept.
func (s *Service) CreateCATFeedImport(ctx context.Context, user uuid.UUID, link string) (core.ImportJob, error) {
	calendarURL, err := CATCalendarURL(link)
	if err != nil {
		return core.ImportJob{}, err
	}
	if s.CATFeed == nil {
		return core.ImportJob{}, errCATUnavailable
	}
	text, err := s.CATFeed.Calendar(ctx, calendarURL)
	if err != nil {
		return core.ImportJob{}, err
	}
	return s.CreateCSVImport(ctx, user, core.SourceCATICS, nil, text)
}
