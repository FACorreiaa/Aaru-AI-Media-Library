package sports

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"bytes"
	"context"
	"encoding/json"
	"math"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// TheSportsDBBaseURL is the provider's host; v2 and v1 hang under it.
const TheSportsDBBaseURL = "https://www.thesportsdb.com"

// TheSportsDB is SPT-001's provider: leagues, teams, players, schedules, livescores and TV
// listings for every sport Aaru shows (football, basketball, American football, UFC, WWE…).
// Premium key, 100 requests a minute. v2 sends the key in `X-API-KEY`; the two v1 calls v2
// lacks (a league's day, an event's TV) carry it in the path. Images are referenced, never
// hosted.
type TheSportsDB struct {
	Client *provider.Client
	APIKey string
	// BaseURL defaults to TheSportsDBBaseURL; tests point it at a stub.
	BaseURL string
}

// NewTheSportsDB paces at 90 a minute with a small burst, so a cold Favorites tab fills fast
// without tripping the 429 (SPT-001).
func NewTheSportsDB(apiKey string, transport provider.Transport) *TheSportsDB {
	return &TheSportsDB{Client: provider.NewClient("thesportsdb", transport, provider.NewPacer(1.5, 10)), APIKey: apiKey}
}

var _ Listing = (*TheSportsDB)(nil)

// Search is entities by name, sent as an underscored lowercase slug.
func (t *TheSportsDB) Search(ctx context.Context, kind EntityKind, query string) ([]Entity, error) {
	slug := strings.Join(strings.Fields(strings.ToLower(strings.TrimSpace(query))), "_")
	out := []Entity{}
	if slug == "" {
		return out, nil
	}
	rows, err := t.v2(ctx, "search/"+string(kind)+"/"+slug)
	if err != nil {
		return nil, err
	}
	for _, row := range rows.rows("search") {
		if e := wireEntity(row, kind); e != nil {
			out = append(out, *e)
		}
	}
	return out, nil
}

// Lookup is one entity by id; nil on a 404 or an empty answer.
func (t *TheSportsDB) Lookup(ctx context.Context, kind EntityKind, id string) (*Entity, error) {
	rows, err := t.v2(ctx, "lookup/"+string(kind)+"/"+id)
	if provider.IsNotFound(err) {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	if err != nil {
		return nil, err
	}
	found := rows.rows("lookup")
	if len(found) == 0 {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	return wireEntity(found[0], kind), nil
}

// Schedule is a team's or league's next or previous events; players have none.
func (t *TheSportsDB) Schedule(ctx context.Context, direction ScheduleDirection, kind EntityKind, id string) ([]Event, error) {
	if kind == KindPlayer {
		return []Event{}, nil
	}
	rows, err := t.v2(ctx, "schedule/"+string(direction)+"/"+string(kind)+"/"+id)
	if err != nil {
		return nil, err
	}
	return events(rows.rows("schedule"), wireEvent), nil
}

// Events is a league's events on one UTC day.
func (t *TheSportsDB) Events(ctx context.Context, day, leagueID string) ([]Event, error) {
	rows, err := t.v1(ctx, "eventsday.php", map[string]string{"d": day, "l": leagueID})
	if err != nil {
		return nil, err
	}
	return events(rows.rows("events"), wireEvent), nil
}

// Event is one event by id; nil on a 404 or an empty answer.
func (t *TheSportsDB) Event(ctx context.Context, id string) (*Event, error) {
	rows, err := t.v2(ctx, "lookup/event/"+id)
	if provider.IsNotFound(err) {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	if err != nil {
		return nil, err
	}
	found := rows.rows("lookup")
	if len(found) == 0 {
		return nil, nil //nolint:nilnil // none, as Swift's optional
	}
	return wireEvent(found[0]), nil
}

// Live is every event live right now.
func (t *TheSportsDB) Live(ctx context.Context) ([]Event, error) {
	rows, err := t.v2(ctx, "livescore/all")
	if err != nil {
		return nil, err
	}
	return events(rows.rows("livescore"), wireLiveScore), nil
}

// Broadcasts is an event's TV listings.
func (t *TheSportsDB) Broadcasts(ctx context.Context, eventID string) ([]Broadcast, error) {
	rows, err := t.v1(ctx, "lookuptv.php", map[string]string{"id": eventID})
	if err != nil {
		return nil, err
	}
	out := []Broadcast{}
	for _, row := range rows.rows("tvevent") {
		if channel := row.text("strChannel"); channel != nil {
			out = append(out, Broadcast{Channel: *channel, Country: row.text("strCountry"), LogoURL: row.url("strLogo")})
		}
	}
	return out, nil
}

// Status reads the provider's free text loosely: "NS", "Not Started", "FT", "Match Finished",
// "AET", "PST", "CANC", "1H", "HT", "Q3"… Anything unknown with a clock is live.
func Status(text, postponed *string) EventStatus {
	if postponed != nil && strings.ToLower(*postponed) == "yes" {
		return StatusPostponed
	}
	value := ""
	if text != nil {
		value = strings.ToLower(strings.Trim(*text, " \t"))
	}
	switch value {
	case "", "ns", "not started", "tbd", "time to be defined", "scheduled":
		return StatusScheduled
	case "ft", "aet", "pen", "ap", "aot", "ft/ot", "final", "awarded", "awd", "wo":
		return StatusFinished
	case "pst", "postponed", "delayed", "susp", "suspended", "int", "interrupted":
		return StatusPostponed
	case "canc", "cancelled", "canceled", "abd", "abandoned":
		return StatusCancelled
	}
	switch {
	case strings.Contains(value, "finish") || strings.HasPrefix(value, "final") || strings.HasPrefix(value, "after"):
		return StatusFinished
	case strings.Contains(value, "postpon"):
		return StatusPostponed
	case strings.Contains(value, "cancel") || strings.Contains(value, "abandon"):
		return StatusCancelled
	case strings.Contains(value, "not started"):
		return StatusScheduled
	}
	return StatusLive
}

// parseInstant reads an ISO 8601 internet date-time without fractions, as Foundation's default
// ISO8601DateFormatter does.
func parseInstant(s string) (time.Time, bool) {
	if strings.Contains(s, ".") {
		return time.Time{}, false
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return time.Time{}, false
	}
	return t.UTC(), true
}

// Instant is `2026-10-24T14:00:00` (UTC, no zone) or with an offset; else the day and time fields.
func Instant(timestamp, day, clock *string) *time.Time {
	if timestamp != nil && *timestamp != "" {
		if t, ok := parseInstant(*timestamp); ok {
			return &t
		}
		if t, ok := parseInstant(*timestamp + "Z"); ok {
			return &t
		}
	}
	if day == nil || core.Length(*day) != 10 || clock == nil || core.Length(*clock) < 5 ||
		strings.HasPrefix(*clock, "00:00:00+") {
		return nil
	}
	c := []rune(*clock)
	hms := string(c[:5]) + ":00"
	if len(c) >= 8 {
		hms = string(c[:8])
	}
	if t, ok := parseInstant(*day + "T" + hms + "Z"); ok {
		return &t
	}
	return nil
}

func (t *TheSportsDB) base() string {
	if t.BaseURL == "" {
		return TheSportsDBBaseURL
	}
	return strings.TrimSuffix(t.BaseURL, "/")
}

// escapePath escapes each segment of a path, keeping its slashes.
func escapePath(path string) string {
	parts := strings.Split(path, "/")
	for i, p := range parts {
		parts[i] = url.PathEscape(p)
	}
	return strings.Join(parts, "/")
}

func (t *TheSportsDB) v2(ctx context.Context, path string) (wireRows, error) {
	body, err := t.Client.Data(ctx, provider.Request{
		URL:     t.base() + "/api/v2/json/" + escapePath(path),
		Headers: [][2]string{{"Accept", "application/json"}, {"X-API-KEY", t.APIKey}},
	})
	if err != nil {
		return nil, err
	}
	return decodeRows(body)
}

func (t *TheSportsDB) v1(ctx context.Context, file string, query map[string]string) (wireRows, error) {
	keys := make([]string, 0, len(query))
	for k := range query {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, url.QueryEscape(k)+"="+url.QueryEscape(query[k]))
	}
	body, err := t.Client.Data(ctx, provider.Request{
		URL:     t.base() + "/api/v1/json/" + url.PathEscape(t.APIKey) + "/" + file + "?" + strings.Join(parts, "&"),
		Headers: [][2]string{{"Accept", "application/json"}},
	})
	if err != nil {
		return nil, err
	}
	return decodeRows(body)
}

// MARK: - TheSportsDB wire shapes (private to this adapter)

// wireRows is every answer: `{"<key>": [rows]}`, where the key varies by call and an empty
// answer is `null` or a sentence ("No data found").
type wireRows map[string][]wireRow

// wireRow is one row; a field may be a string, a number or null, depending on the row.
type wireRow map[string]json.RawMessage

func decodeRows(body []byte) (wireRows, error) {
	var top map[string]json.RawMessage
	if err := json.Unmarshal(body, &top); err != nil || top == nil {
		return nil, provider.NewError("thesportsdb", provider.KindMalformed)
	}
	out := wireRows{}
	for key, raw := range top {
		var list []json.RawMessage
		if err := json.Unmarshal(raw, &list); err != nil || list == nil {
			continue
		}
		rows := []wireRow{}
		for _, item := range list {
			var row wireRow
			// A bad row is skipped, not the whole answer.
			if err := json.Unmarshal(item, &row); err != nil || row == nil {
				continue
			}
			rows = append(rows, row)
		}
		out[key] = rows
	}
	return out, nil
}

func (r wireRows) rows(key string) []wireRow { return r[key] }

// text is a field read loosely: a trimmed non-empty string, or a number as text.
func (r wireRow) text(field string) *string {
	raw, ok := r[field]
	if !ok {
		return nil
	}
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || raw[0] == 'n' || raw[0] == 't' || raw[0] == 'f' || raw[0] == '{' || raw[0] == '[' {
		return nil
	}
	if raw[0] == '"' {
		var s string
		if err := json.Unmarshal(raw, &s); err != nil {
			return nil
		}
		s = strings.TrimSpace(s)
		if s == "" {
			return nil
		}
		return &s
	}
	if i, err := strconv.ParseInt(string(raw), 10, 64); err == nil {
		s := strconv.FormatInt(i, 10)
		return &s
	}
	f, err := strconv.ParseFloat(string(raw), 64)
	if err != nil {
		return nil
	}
	if f == math.Trunc(f) && math.Abs(f) < 1<<53 {
		s := strconv.FormatInt(int64(f), 10)
		return &s
	}
	s := strconv.FormatFloat(f, 'g', -1, 64)
	return &s
}

// int is a field as a whole number: "2", 2 or "2.0".
func (r wireRow) int(field string) *int {
	text := r.text(field)
	if text == nil {
		return nil
	}
	if i, err := strconv.Atoi(*text); err == nil {
		return &i
	}
	f, err := strconv.ParseFloat(*text, 64)
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return nil
	}
	i := int(f)
	return &i
}

// url is a field that is a web link.
func (r wireRow) url(field string) *string {
	text := r.text(field)
	if text == nil || !strings.HasPrefix(*text, "http") || strings.ContainsAny(*text, " \t\n") {
		return nil
	}
	if _, err := url.Parse(*text); err != nil {
		return nil
	}
	return text
}

func or(a, b *string) *string {
	if a != nil {
		return a
	}
	return b
}

func wireEntity(r wireRow, kind EntityKind) *Entity {
	sport := ""
	if s := r.text("strSport"); s != nil {
		sport = *s
	}
	switch kind {
	case KindLeague:
		id, name := r.text("idLeague"), r.text("strLeague")
		if id == nil || name == nil {
			return nil
		}
		return &Entity{
			Kind: KindLeague, ID: *id, Name: *name, Sport: sport, BadgeURL: or(r.url("strBadge"), r.url("strLogo")),
			Country: r.text("strCountry"), LeagueID: id,
		}
	case KindTeam:
		id, name := r.text("idTeam"), r.text("strTeam")
		if id == nil || name == nil {
			return nil
		}
		return &Entity{
			Kind: KindTeam, ID: *id, Name: *name, Sport: sport, BadgeURL: or(r.url("strBadge"), r.url("strLogo")),
			Country: r.text("strCountry"), LeagueID: r.text("idLeague"),
		}
	case KindPlayer:
		id, name := r.text("idPlayer"), r.text("strPlayer")
		if id == nil || name == nil {
			return nil
		}
		return &Entity{
			Kind: KindPlayer, ID: *id, Name: *name, Sport: sport, BadgeURL: or(r.url("strCutout"), r.url("strThumb")),
			Country: r.text("strNationality"), TeamID: r.text("idTeam"), TeamName: r.text("strTeam"),
		}
	}
	return nil
}

func events(rows []wireRow, read func(wireRow) *Event) []Event {
	out := []Event{}
	for _, row := range rows {
		if e := read(row); e != nil {
			out = append(out, *e)
		}
	}
	return out
}

func wireEvent(r wireRow) *Event {
	id, name := r.text("idEvent"), r.text("strEvent")
	if id == nil || name == nil {
		return nil
	}
	startsAt := Instant(r.text("strTimestamp"), r.text("dateEvent"), r.text("strTime"))
	var day string
	switch date := r.text("dateEvent"); {
	case date != nil:
		day = core.Prefix(*date, 10)
	case startsAt != nil:
		day = startsAt.UTC().Format(time.DateOnly)
	default:
		return nil
	}
	e := &Event{
		ID: *id, Name: *name, LeagueID: r.text("idLeague"), League: r.text("strLeague"),
		LeagueBadgeURL: r.url("strLeagueBadge"), StartsAt: startsAt, Day: day,
		Status:   Status(r.text("strStatus"), r.text("strPostponed")),
		Progress: r.text("strProgress"), Venue: r.text("strVenue"), ImageURL: or(r.url("strThumb"), r.url("strPoster")),
	}
	if s := r.text("strSport"); s != nil {
		e.Sport = *s
	}
	if home := r.text("strHomeTeam"); home != nil {
		e.Home = &Side{ID: r.text("idHomeTeam"), Name: *home, BadgeURL: r.url("strHomeTeamBadge"), Score: r.int("intHomeScore")}
	}
	if away := r.text("strAwayTeam"); away != nil {
		e.Away = &Side{ID: r.text("idAwayTeam"), Name: *away, BadgeURL: r.url("strAwayTeamBadge"), Score: r.int("intAwayScore")}
	}
	if round := r.int("intRound"); round != nil && *round > 0 {
		s := "Round " + strconv.Itoa(*round)
		e.Round = &s
	}
	return e
}

func wireLiveScore(r wireRow) *Event {
	id, home, away, date := r.text("idEvent"), r.text("strHomeTeam"), r.text("strAwayTeam"), r.text("dateEvent")
	if id == nil || home == nil || away == nil || date == nil {
		return nil
	}
	day := core.Prefix(*date, 10)
	e := &Event{
		ID: *id, Name: *home + " vs " + *away, LeagueID: r.text("idLeague"), League: r.text("strLeague"),
		Home:     &Side{ID: r.text("idHomeTeam"), Name: *home, BadgeURL: r.url("strHomeTeamBadge"), Score: r.int("intHomeScore")},
		Away:     &Side{ID: r.text("idAwayTeam"), Name: *away, BadgeURL: r.url("strAwayTeamBadge"), Score: r.int("intAwayScore")},
		StartsAt: Instant(nil, &day, r.text("strEventTime")), Day: day,
		// The feed puts the clock in `strProgress` and sometimes leaves `strStatus` blank.
		Status:   Status(or(r.text("strStatus"), r.text("strProgress")), nil),
		Progress: r.text("strProgress"),
	}
	if s := r.text("strSport"); s != nil {
		e.Sport = *s
	}
	return e
}
