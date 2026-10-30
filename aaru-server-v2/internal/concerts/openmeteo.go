package concerts

import (
	"aaru-go-api/internal/provider"
	"context"
	"net/url"
	"strings"
)

// OpenMeteoBaseURL is Open-Meteo's geocoder.
const OpenMeteoBaseURL = "https://geocoding-api.open-meteo.com/v1/search"

// OpenMeteo is MUS-003's city search for "Concerts near": Open-Meteo's geocoder turns the city a
// user types into a point. No key; free for non-commercial use (revisit if Aaru charges). Only
// the typed name is sent.
type OpenMeteo struct {
	Client *provider.Client
	// BaseURL defaults to OpenMeteoBaseURL; tests point it at a stub.
	BaseURL string
}

// NewOpenMeteo is the production place search: a few lookups a user, only while they type.
func NewOpenMeteo(transport provider.Transport) *OpenMeteo {
	return &OpenMeteo{Client: provider.NewClient("open-meteo", transport, provider.NewPacer(2, 5))}
}

var _ PlaceSearcher = (*OpenMeteo)(nil)

type omResult struct {
	Name        *string  `json:"name"`
	Latitude    *float64 `json:"latitude"`
	Longitude   *float64 `json:"longitude"`
	Country     *string  `json:"country"`
	CountryCode *string  `json:"country_code"`
	Admin1      *string  `json:"admin1"`
}

// Places is up to eight places matching the typed name.
func (o *OpenMeteo) Places(ctx context.Context, query string) ([]Place, error) {
	base := o.BaseURL
	if base == "" {
		base = OpenMeteoBaseURL
	}
	request := provider.Request{
		URL:     base + "?name=" + url.QueryEscape(query) + "&count=8&language=en&format=json",
		Headers: [][2]string{{"Accept", "application/json"}},
	}
	// Results is absent, not empty, when nothing matches.
	var page struct {
		Results []omResult `json:"results"`
	}
	if err := o.Client.DecodeJSON(ctx, request, &page); err != nil {
		return nil, err
	}
	out := []Place{}
	for _, r := range page.Results {
		if r.Name == nil || r.Latitude == nil || r.Longitude == nil {
			return nil, provider.NewError("open-meteo", provider.KindMalformed)
		}
	}
	for _, r := range page.Results {
		point, ok := NewGeoPoint(*r.Latitude, *r.Longitude)
		if !ok {
			continue
		}
		place := Place{Name: *r.Name, Region: r.Admin1, Country: r.Country, Point: point}
		if r.CountryCode != nil {
			code := strings.ToUpper(*r.CountryCode)
			place.CountryCode = &code
		}
		out = append(out, place)
	}
	return out, nil
}
