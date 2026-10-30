package concerts

import (
	"aaru-go-api/internal/provider"
	"context"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// CallBudget is Ticketmaster's daily allowance: the free tier allows 5,000 calls a day, Aaru
// stops at Limit (UTC day) and serves what it has cached, so a busy day never runs the key into
// its hard cap.
type CallBudget struct {
	Limit int
	mu    sync.Mutex
	day   string
	used  int
}

// NewCallBudget allows limit calls a UTC day.
func NewCallBudget(limit int) *CallBudget { return &CallBudget{Limit: limit} }

// Take takes one call from today's budget; false when it is spent.
func (b *CallBudget) Take(now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	today := now.UTC().Format(time.DateOnly)
	if today != b.day {
		b.day = today
		b.used = 0
	}
	if b.used >= b.Limit {
		return false
	}
	b.used++
	return true
}

// Ticketmaster is MUS-003's Ticketmaster Discovery API v2: music events near a point or by
// performer, and performers by name with their MusicBrainz links. Free key, 5,000 calls a day, 5
// a second. Terms: cache only for short periods, link out to Ticketmaster for tickets, never
// resell.
type Ticketmaster struct {
	Client *provider.Client
	APIKey string
	Budget *CallBudget
	// BaseURL defaults to TicketmasterBaseURL; tests point it at a stub.
	BaseURL string
	// Now is the clock the budget reads; time.Now by default.
	Now func() time.Time
}

const (
	// TicketmasterBaseURL is the Discovery API's root.
	TicketmasterBaseURL = "https://app.ticketmaster.com/discovery/v2"
	// PageSize is 50 a page.
	PageSize = 50
	// MaxPage: Ticketmaster refuses to page past 1,000 results.
	MaxPage = 10
	// DailyCalls is where Aaru stops for the day (Ticketmaster's cap is 5,000).
	DailyCalls = 4500
)

// NewTicketmaster is the production adapter: four requests a second, 4,500 a day (MUS-003).
func NewTicketmaster(apiKey string, transport provider.Transport) *Ticketmaster {
	return &Ticketmaster{
		Client: provider.NewClient("ticketmaster", transport, provider.NewPacer(4, 4)),
		APIKey: apiKey,
		Budget: NewCallBudget(DailyCalls),
	}
}

var _ Listing = (*Ticketmaster)(nil)

// Near is one page of music events around the point's cell.
func (t *Ticketmaster) Near(ctx context.Context, point GeoPoint, radiusKm, page int, from time.Time) (Results, error) {
	return t.musicEvents(ctx, page, from, map[string]string{
		"geoPoint": point.Geohash(),
		"radius":   strconv.Itoa(radiusKm),
		"unit":     "km",
	})
}

// Search is one page of music events by keyword or performer, around near when given.
func (t *Ticketmaster) Search(ctx context.Context, match Match, near *Area, page int, from time.Time) (Results, error) {
	query := map[string]string{}
	if match.PerformerID != "" {
		query["attractionId"] = match.PerformerID
	} else {
		query["keyword"] = match.Keyword
	}
	if near != nil {
		query["geoPoint"] = near.Point.Geohash()
		query["radius"] = strconv.Itoa(near.RadiusKm)
		query["unit"] = "km"
	}
	return t.musicEvents(ctx, page, from, query)
}

// Performing is the upcoming events of these performers.
func (t *Ticketmaster) Performing(ctx context.Context, attractionIDs []string, from time.Time) ([]Concert, error) {
	if len(attractionIDs) == 0 {
		return []Concert{}, nil
	}
	var page tmEventPage
	if err := t.get(ctx, "events.json", map[string]string{
		"attractionId":  strings.Join(attractionIDs, ","),
		"sort":          "date,asc",
		"startDateTime": Timestamp(from),
		"size":          strconv.Itoa(PageSize),
	}, &page); err != nil {
		return nil, err
	}
	return page.concerts(), nil
}

// Attractions is performers whose name matches.
func (t *Ticketmaster) Attractions(ctx context.Context, name string) ([]Attraction, error) {
	var page tmAttractionPage
	if err := t.get(ctx, "attractions.json", map[string]string{
		"keyword":            name,
		"classificationName": "music",
		"size":               "20",
	}, &page); err != nil {
		return nil, err
	}
	out := []Attraction{}
	if page.Embedded == nil {
		return out, nil
	}
	for _, a := range page.Embedded.Attractions {
		ids := []string{}
		if a.ExternalLinks != nil {
			for _, link := range a.ExternalLinks.MusicBrainz {
				if link.ID != nil {
					ids = append(ids, strings.ToLower(*link.ID))
				}
			}
		}
		out = append(out, Attraction{ID: *a.ID, Name: *a.Name, MusicBrainzIDs: ids, ImageURL: pickImage(a.Images, 200)})
	}
	return out, nil
}

// Event is one event by id; nil when Ticketmaster answers 404.
func (t *Ticketmaster) Event(ctx context.Context, id string) (*Concert, error) {
	var event tmEvent
	if err := t.get(ctx, "events/"+url.PathEscape(id)+".json", nil, &event); err != nil {
		if provider.IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return event.concert(), nil
}

// musicEvents is one page of music events from `from` on, soonest first, narrowed by query.
func (t *Ticketmaster) musicEvents(ctx context.Context, page int, from time.Time, query map[string]string) (Results, error) {
	merged := map[string]string{
		"classificationName": "music",
		"sort":               "date,asc",
		"startDateTime":      Timestamp(from),
		"size":               strconv.Itoa(PageSize),
		"page":               strconv.Itoa(max(0, page-1)),
	}
	for k, v := range query {
		merged[k] = v
	}
	var response tmEventPage
	if err := t.get(ctx, "events.json", merged, &response); err != nil {
		return Results{}, err
	}
	current, pages := 0, 0
	if response.Page != nil {
		if response.Page.Number != nil {
			current = *response.Page.Number
		}
		if response.Page.TotalPages != nil {
			pages = *response.Page.TotalPages
		}
	}
	return Results{Concerts: response.concerts(), HasMore: current+1 < pages && current+1 < MaxPage}, nil
}

// Timestamp is `2026-10-21T18:00:00Z`: Ticketmaster wants seconds and a literal Z, no fractions.
func Timestamp(t time.Time) string {
	return t.UTC().Format("2006-01-02T15:04:05Z")
}

// get spends one call of the day's budget, then sends query (sorted by name, the key last).
func (t *Ticketmaster) get(ctx context.Context, path string, query map[string]string, into interface{ valid() bool }) error {
	now := time.Now
	if t.Now != nil {
		now = t.Now
	}
	if !t.Budget.Take(now()) {
		return provider.NewError("ticketmaster", provider.KindUnavailable)
	}
	base := t.BaseURL
	if base == "" {
		base = TicketmasterBaseURL
	}
	keys := make([]string, 0, len(query))
	for k := range query {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys)+1)
	for _, k := range keys {
		parts = append(parts, url.QueryEscape(k)+"="+url.QueryEscape(query[k]))
	}
	parts = append(parts, "apikey="+url.QueryEscape(t.APIKey))
	request := provider.Request{
		URL:     strings.TrimSuffix(base, "/") + "/" + path + "?" + strings.Join(parts, "&"),
		Headers: [][2]string{{"Accept", "application/json"}},
	}
	if err := t.Client.DecodeJSON(ctx, request, into); err != nil {
		return err
	}
	if !into.valid() {
		return provider.NewError("ticketmaster", provider.KindMalformed)
	}
	return nil
}

// MARK: - Ticketmaster wire shapes (private to this adapter)
//
// Fields Swift decoded as required are pointers here and checked by valid(): a row missing one
// fails the whole answer as malformed, as Swift's Decodable did.

type tmPageInfo struct {
	Number     *int `json:"number"`
	TotalPages *int `json:"totalPages"`
}

type tmEventPage struct {
	Embedded *struct {
		Events []tmEvent `json:"events"`
	} `json:"_embedded"`
	Page *tmPageInfo `json:"page"`
}

func (p *tmEventPage) events() []tmEvent {
	if p.Embedded == nil {
		return nil
	}
	return p.Embedded.Events
}

func (p *tmEventPage) valid() bool {
	for i := range p.events() {
		if !p.Embedded.Events[i].valid() {
			return false
		}
	}
	return true
}

func (p *tmEventPage) concerts() []Concert {
	out := []Concert{}
	for i := range p.events() {
		if c := p.Embedded.Events[i].concert(); c != nil {
			out = append(out, *c)
		}
	}
	return out
}

type tmEventStart struct {
	LocalDate      *string `json:"localDate"`
	LocalTime      *string `json:"localTime"`
	DateTime       *string `json:"dateTime"`
	TimeTBA        *bool   `json:"timeTBA"`
	NoSpecificTime *bool   `json:"noSpecificTime"`
}

type tmEventDates struct {
	Start  *tmEventStart `json:"start"`
	Status *struct {
		Code *string `json:"code"`
	} `json:"status"`
}

type tmImage struct {
	URL      *string  `json:"url"`
	Ratio    *string  `json:"ratio"`
	Width    *float64 `json:"width"`
	Fallback *bool    `json:"fallback"`
}

type tmNamed struct {
	Name *string `json:"name"`
}

// tmVenueLocation: Ticketmaster sends the coordinates as strings.
type tmVenueLocation struct {
	Latitude  *string `json:"latitude"`
	Longitude *string `json:"longitude"`
}

func (l *tmVenueLocation) point() *GeoPoint {
	if l == nil || l.Latitude == nil || l.Longitude == nil {
		return nil
	}
	lat, err1 := strconv.ParseFloat(*l.Latitude, 64)
	lon, err2 := strconv.ParseFloat(*l.Longitude, 64)
	if err1 != nil || err2 != nil {
		return nil
	}
	if p, ok := NewGeoPoint(lat, lon); ok {
		return &p
	}
	return nil
}

type tmVenue struct {
	Name     *string          `json:"name"`
	City     *tmNamed         `json:"city"`
	Country  *tmNamed         `json:"country"`
	Location *tmVenueLocation `json:"location"`
}

type tmEvent struct {
	ID       *string       `json:"id"`
	Name     *string       `json:"name"`
	URL      *string       `json:"url"`
	Dates    *tmEventDates `json:"dates"`
	Images   []tmImage     `json:"images"`
	Distance *float64      `json:"distance"`
	Units    *string       `json:"units"`
	Embedded *struct {
		Venues      []tmVenue `json:"venues"`
		Attractions []tmNamed `json:"attractions"`
	} `json:"_embedded"`
}

func (e *tmEvent) valid() bool {
	if e.ID == nil || e.Name == nil {
		return false
	}
	for _, image := range e.Images {
		if image.URL == nil {
			return false
		}
	}
	if e.Embedded != nil {
		for _, a := range e.Embedded.Attractions {
			if a.Name == nil {
				return false
			}
		}
	}
	return true
}

var catalogDatePattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}`)

// catalogDate is the leading `YYYY-MM-DD` of a provider date, if any.
func catalogDate(s *string) (string, bool) {
	if s == nil {
		return "", false
	}
	m := catalogDatePattern.FindString(*s)
	return m, m != ""
}

// parseURL is a link Aaru can send on; nil for an empty or unparseable one.
func parseURL(s *string) *string {
	if s == nil || *s == "" || strings.ContainsAny(*s, " \t\n") {
		return nil
	}
	if _, err := url.Parse(*s); err != nil {
		return nil
	}
	v := *s
	return &v
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

// concert is nil for an event Aaru cannot show: no date, no ticket page, or cancelled.
func (e *tmEvent) concert() *Concert {
	var start *tmEventStart
	if e.Dates != nil {
		start = e.Dates.Start
	}
	var localDatePtr *string
	if start != nil {
		localDatePtr = start.LocalDate
	}
	localDate, ok := catalogDate(localDatePtr)
	link := parseURL(e.URL)
	if !ok || link == nil {
		return nil
	}
	if e.Dates != nil && e.Dates.Status != nil && e.Dates.Status.Code != nil && *e.Dates.Status.Code == "cancelled" {
		return nil
	}
	exactTime := start == nil || ((start.TimeTBA == nil || !*start.TimeTBA) && (start.NoSpecificTime == nil || !*start.NoSpecificTime))
	c := &Concert{ID: *e.ID, Name: *e.Name, Artists: []string{}, LocalDate: localDate, URL: *link, ImageURL: pickImage(e.Images, 500)}
	if e.Embedded != nil {
		for _, a := range e.Embedded.Attractions {
			c.Artists = append(c.Artists, *a.Name)
		}
		if len(e.Embedded.Venues) > 0 {
			venue := e.Embedded.Venues[0]
			c.Venue = venue.Name
			if venue.City != nil {
				c.City = venue.City.Name
			}
			if venue.Country != nil {
				c.Country = venue.Country.Name
			}
			c.VenuePoint = venue.Location.point()
		}
	}
	if exactTime && start != nil {
		if start.DateTime != nil {
			if t, ok := parseInstant(*start.DateTime); ok {
				c.StartsAt = &t
			}
		}
		if start.LocalTime != nil {
			lt := prefixRunes(*start.LocalTime, 5)
			c.LocalTime = &lt
		}
	}
	if e.Distance != nil {
		d := *e.Distance
		if e.Units != nil && strings.HasPrefix(strings.ToUpper(*e.Units), "MI") {
			d *= 1.609344
		}
		c.DistanceKm = &d
	}
	return c
}

// pickImage is the smallest wide image at least minWidth across; Ticketmaster's own
// placeholders aside.
func pickImage(images []tmImage, minWidth float64) *string {
	var usable []tmImage
	for _, image := range images {
		if image.Fallback == nil || !*image.Fallback {
			usable = append(usable, image)
		}
	}
	var wide []tmImage
	for _, image := range usable {
		if image.Ratio != nil && *image.Ratio == "16_9" {
			wide = append(wide, image)
		}
	}
	width := func(i tmImage) float64 {
		if i.Width == nil {
			return 0
		}
		return *i.Width
	}
	sort.SliceStable(wide, func(a, b int) bool { return width(wide[a]) < width(wide[b]) })
	var pick *tmImage
	for i := range wide {
		if width(wide[i]) >= minWidth {
			pick = &wide[i]
			break
		}
	}
	if pick == nil && len(wide) > 0 {
		pick = &wide[len(wide)-1]
	}
	if pick == nil && len(usable) > 0 {
		pick = &usable[0]
	}
	if pick == nil {
		return nil
	}
	return parseURL(pick.URL)
}

type tmAttraction struct {
	ID            *string `json:"id"`
	Name          *string `json:"name"`
	ExternalLinks *struct {
		MusicBrainz []struct {
			ID *string `json:"id"`
		} `json:"musicbrainz"`
	} `json:"externalLinks"`
	Images []tmImage `json:"images"`
}

type tmAttractionPage struct {
	Embedded *struct {
		Attractions []tmAttraction `json:"attractions"`
	} `json:"_embedded"`
}

func (p *tmAttractionPage) valid() bool {
	if p.Embedded == nil {
		return true
	}
	for _, a := range p.Embedded.Attractions {
		if a.ID == nil || a.Name == nil {
			return false
		}
		for _, image := range a.Images {
			if image.URL == nil {
				return false
			}
		}
	}
	return true
}

func prefixRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}
