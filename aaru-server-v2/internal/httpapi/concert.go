package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/concerts"
	"context"
	"errors"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// ConcertHandlers.swift: MUS-003 · concerts near a place and for the user's artists, and the
// "Concerts near" city; MUS-010 · concerts by artist.

var errNoConcertPlace = apperr.New(http.StatusConflict, "no_place", "Choose a city for concerts in Settings, or use your location.")

func (s *Server) GetConcertsNear(ctx context.Context, req api.GetConcertsNearRequestObject) (api.GetConcertsNearResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	page, err := concertPage(req.Body.Page)
	if err != nil {
		return nil, err
	}
	point, err := oneOffPoint(req.Body.Latitude, req.Body.Longitude)
	if err != nil {
		return nil, err
	}
	nearby, err := s.Concerts.Near(ctx, userID, point, int(req.Body.RadiusKm), page)
	if errors.Is(err, concerts.ErrNoPlace) {
		return nil, errNoConcertPlace
	}
	if err != nil {
		return nil, err
	}
	return api.GetConcertsNear200JSONResponse{
		Place: concertPlaceDTO(nearby.Place), RadiusKm: nearby.RadiusKm, Items: concertDTOs(nearby.Results.Concerts),
		Page: nearby.Page, HasMore: nearby.Results.HasMore, Unavailable: nearby.Unavailable,
	}, nil
}

func (s *Server) SearchConcerts(ctx context.Context, req api.SearchConcertsRequestObject) (api.SearchConcertsResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	query, err := artistName(req.Body.Q)
	if err != nil {
		return nil, err
	}
	if id := req.Body.PerformerId; id != nil && !isPerformerID(*id) {
		return nil, apperr.Validation("performerId", "Not a performer from the list.")
	}
	page, err := concertPage(req.Body.Page)
	if err != nil {
		return nil, err
	}
	point, err := oneOffPoint(req.Body.Latitude, req.Body.Longitude)
	if err != nil {
		return nil, err
	}
	scope := concerts.ScopeNear
	if req.Body.Scope == api.ConcertSearchScopeAnywhere {
		scope = concerts.ScopeAnywhere
	}
	found, err := s.Concerts.Search(ctx, concerts.Search{
		Query: query, PerformerID: req.Body.PerformerId, Scope: scope, RadiusKm: int(req.Body.RadiusKm), Page: page,
	}, userID, point)
	if errors.Is(err, concerts.ErrNoPlace) {
		return nil, errNoConcertPlace
	}
	if err != nil {
		return nil, err
	}
	return api.SearchConcerts200JSONResponse{
		Query: found.Query, PerformerId: found.PerformerID, Scope: api.ConcertSearchScope(found.Scope),
		Place: concertPlaceDTO(found.Place), RadiusKm: found.RadiusKm, Items: concertDTOs(found.Results.Concerts),
		Page: found.Page, HasMore: found.Results.HasMore, Unavailable: found.Unavailable,
	}, nil
}

func (s *Server) SearchConcertPerformers(ctx context.Context, req api.SearchConcertPerformersRequestObject) (api.SearchConcertPerformersResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	query, err := artistName(req.Body.Q)
	if err != nil {
		return nil, err
	}
	found, ok := s.Concerts.Performers(ctx, query)
	items := make([]api.ConcertPerformer, 0, len(found))
	for _, p := range found {
		items = append(items, api.ConcertPerformer{Id: p.ID, Name: p.Name, ImageUrl: p.ImageURL})
	}
	return api.SearchConcertPerformers200JSONResponse{Items: items, Unavailable: !ok}, nil
}

func (s *Server) GetArtistConcerts(ctx context.Context, _ api.GetArtistConcertsRequestObject) (api.GetArtistConcertsResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	found, err := s.Concerts.ForLibrary(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetArtistConcerts200JSONResponse{
		Items: concertDTOs(found.Concerts), Matched: found.Matched, Pending: found.Pending, Unavailable: found.Unavailable,
	}, nil
}

func (s *Server) SearchConcertPlaces(ctx context.Context, req api.SearchConcertPlacesRequestObject) (api.SearchConcertPlacesResponseObject, error) {
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	query := strings.TrimSpace(req.Params.Q)
	if n := utf8.RuneCountInString(query); n < 2 || n > 100 {
		return nil, apperr.Validation("q", "Type 2 to 100 characters.")
	}
	places, err := s.Concerts.SearchPlaces(ctx, query)
	if err != nil {
		return nil, err
	}
	items := make([]api.ConcertPlace, 0, len(places))
	for i := range places {
		items = append(items, *concertPlaceDTO(&places[i]))
	}
	return api.SearchConcertPlaces200JSONResponse{Items: items}, nil
}

func (s *Server) GetConcertPlace(ctx context.Context, _ api.GetConcertPlaceRequestObject) (api.GetConcertPlaceResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	place, err := s.Concerts.Store.Place(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.GetConcertPlace200JSONResponse(s.concertPlaceSetting(place)), nil
}

func (s *Server) SaveConcertPlace(ctx context.Context, req api.SaveConcertPlaceRequestObject) (api.SaveConcertPlaceResponseObject, error) {
	if req.Body == nil {
		return nil, apperr.BadRequest()
	}
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	body := req.Body
	name := strings.TrimSpace(body.Name)
	if n := utf8.RuneCountInString(name); n < 1 || n > 200 {
		return nil, apperr.Validation("name", "1 to 200 characters.")
	}
	point, ok := concerts.NewGeoPoint(wireNumber(body.Latitude), wireNumber(body.Longitude))
	if !ok {
		return nil, apperr.Validation("latitude", "Not a position on Earth.")
	}
	var code *string
	if body.CountryCode != nil {
		upper := strings.ToUpper(*body.CountryCode)
		if utf8.RuneCountInString(upper) != 2 || strings.IndexFunc(upper, func(r rune) bool { return !unicode.IsLetter(r) }) >= 0 {
			return nil, apperr.Validation("countryCode", "Two letters, as ISO 3166-1.")
		}
		code = &upper
	}
	place := concerts.Place{Name: name, Region: trimmedField(body.Region), Country: trimmedField(body.Country), CountryCode: code, Point: point}
	if err := s.Concerts.Store.SavePlace(ctx, place, userID, time.Now()); err != nil {
		return nil, err
	}
	saved, err := s.Concerts.Store.Place(ctx, userID)
	if err != nil {
		return nil, err
	}
	return api.SaveConcertPlace200JSONResponse(s.concertPlaceSetting(saved)), nil
}

func (s *Server) DeleteConcertPlace(ctx context.Context, _ api.DeleteConcertPlaceRequestObject) (api.DeleteConcertPlaceResponseObject, error) {
	userID, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.Concerts.Store.DeletePlace(ctx, userID); err != nil {
		return nil, err
	}
	return api.DeleteConcertPlace204Response{}, nil
}

func (s *Server) concertPlaceSetting(place *concerts.Place) api.ConcertPlaceSetting {
	return api.ConcertPlaceSetting{Place: concertPlaceDTO(place), Available: s.Concerts.IsAvailable()}
}

// artistName is an artist's name as typed: trimmed, 2 to 100 characters.
func artistName(text string) (string, error) {
	name := strings.TrimSpace(text)
	if n := utf8.RuneCountInString(name); n < 2 || n > 100 {
		return "", apperr.Validation("q", "Type 2 to 100 characters.")
	}
	return name, nil
}

// isPerformerID is a provider performer id: letters, digits, `-` and `_`, at most 64.
func isPerformerID(id string) bool {
	if len(id) < 1 || len(id) > 64 {
		return false
	}
	for _, r := range id {
		if r > unicode.MaxASCII || (!unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '-' && r != '_') {
			return false
		}
	}
	return true
}

func concertPage(page *int) (int, error) {
	p := 1
	if page != nil {
		p = *page
	}
	if p < 1 || p > concerts.MaxPage {
		return 0, apperr.Validation("page", "Pages run from 1 to "+strconv.Itoa(concerts.MaxPage)+".")
	}
	return p, nil
}

// wireNumber is a JSON number the generated types hold as float32 (openapi `type: number`),
// back as the decimal the client sent, so rounding to two decimals matches the Swift server's
// Double.
func wireNumber(f float32) float64 {
	v, err := strconv.ParseFloat(strconv.FormatFloat(float64(f), 'g', -1, 32), 64)
	if err != nil {
		return float64(f)
	}
	return v
}

// oneOffPoint is a one-off position sent with the request, rounded; nil when neither coordinate was sent.
func oneOffPoint(latitude, longitude *float32) (*concerts.GeoPoint, error) {
	switch {
	case latitude == nil && longitude == nil:
		return nil, nil //nolint:nilnil // none
	case latitude != nil && longitude != nil:
		point, ok := concerts.NewGeoPoint(wireNumber(*latitude), wireNumber(*longitude))
		if !ok {
			return nil, apperr.Validation("latitude", "Not a position on Earth.")
		}
		return &point, nil
	default:
		return nil, apperr.Validation("longitude", "Send latitude and longitude together.")
	}
}

func trimmedField(text *string) *string {
	if text == nil {
		return nil
	}
	t := strings.TrimSpace(*text)
	if t == "" {
		return nil
	}
	if r := []rune(t); len(r) > 200 {
		t = string(r[:200])
	}
	return &t
}

func concertDTOs(list []concerts.Concert) []api.Concert {
	out := make([]api.Concert, 0, len(list))
	for _, c := range list {
		out = append(out, concertDTO(c))
	}
	return out
}

func concertDTO(c concerts.Concert) api.Concert {
	dto := api.Concert{
		Id: c.ID, Name: c.Name, Artists: c.Artists, LocalDate: c.LocalDate, LocalTime: c.LocalTime, Venue: c.Venue,
		City: c.City, Country: c.Country, Url: c.URL, ImageUrl: c.ImageURL,
	}
	if dto.Artists == nil {
		dto.Artists = []string{}
	}
	if c.StartsAt != nil {
		t := apitime.From(*c.StartsAt)
		dto.StartsAt = &t
	}
	if c.DistanceKm != nil {
		d := float32(math.Round(*c.DistanceKm*10) / 10)
		dto.DistanceKm = &d
	}
	return dto
}

func concertPlaceDTO(place *concerts.Place) *api.ConcertPlace {
	if place == nil {
		return nil
	}
	return &api.ConcertPlace{
		Name: place.Name, Region: place.Region, Country: place.Country, CountryCode: place.CountryCode,
		Latitude: float32(place.Point.Latitude), Longitude: float32(place.Point.Longitude),
	}
}
