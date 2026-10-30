package middleware

import (
	"aaru-go-api/internal/apperr"
	"fmt"
	"mime"
	"net/http"

	"github.com/getkin/kin-openapi/openapi3"
	"github.com/getkin/kin-openapi/openapi3filter"
	"github.com/getkin/kin-openapi/routers/gorillamux"
	"github.com/labstack/echo/v4"
)

// Validate refuses with 400 `bad_request` what the Swift server's generated
// decoder refused before a handler ran: a missing required field or parameter,
// a value of the wrong type, an enum value the spec does not list, a malformed
// date-time. Length, range and pattern limits are removed from the spec
// first, because swift-openapi-generator never enforced them: handlers check
// those themselves, with their own 422 messages. Only JSON bodies are checked;
// routes outside the spec pass through.
func Validate(spec *openapi3.T) (echo.MiddlewareFunc, error) {
	loosen(spec)
	spec.Servers = nil
	router, err := gorillamux.NewRouter(spec)
	if err != nil {
		return nil, fmt.Errorf("validation router: %w", err)
	}
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			req := c.Request()
			route, params, err := router.FindRoute(req)
			if err != nil {
				// Not in openapi.yaml (Stremio, MCP, OAuth…) or not a known method:
				// those routes read their own requests, and echo answers the rest.
				return next(c)
			}
			input := &openapi3filter.RequestValidationInput{
				Request:    req,
				PathParams: params,
				Route:      route,
				Options: &openapi3filter.Options{
					AuthenticationFunc: openapi3filter.NoopAuthenticationFunc,
					ExcludeRequestBody: !isJSON(req),
					MultiError:         false,
				},
			}
			if err := openapi3filter.ValidateRequest(req.Context(), input); err != nil {
				return apperr.BadRequest()
			}
			return next(c)
		}
	}, nil
}

func isJSON(req *http.Request) bool {
	if req.ContentLength == 0 && req.Body == http.NoBody {
		return true
	}
	ct := req.Header.Get("Content-Type")
	if ct == "" {
		return false
	}
	mt, _, err := mime.ParseMediaType(ct)
	return err == nil && mt == "application/json"
}

// loosen drops the constraints Swift's decoder ignored, everywhere in the spec.
func loosen(spec *openapi3.T) {
	seen := map[*openapi3.Schema]bool{}
	var walk func(*openapi3.SchemaRef)
	walk = func(ref *openapi3.SchemaRef) {
		if ref == nil || ref.Value == nil || seen[ref.Value] {
			return
		}
		s := ref.Value
		seen[s] = true
		if s.Format == "uuid" {
			// Swift typed these as String: a malformed id is the handler's 404, not a 400.
			s.Format = ""
		}
		s.MinLength, s.MaxLength, s.Pattern = 0, nil, ""
		s.Min, s.Max, s.MultipleOf = nil, nil, nil
		s.ExclusiveMin, s.ExclusiveMax = openapi3.ExclusiveBound{}, openapi3.ExclusiveBound{}
		s.MinItems, s.MaxItems, s.UniqueItems = 0, nil, false
		s.MinProps, s.MaxProps = 0, nil
		walk(s.Items)
		walk(s.Not)
		for _, p := range s.Properties {
			walk(p)
		}
		if s.AdditionalProperties.Schema != nil {
			walk(s.AdditionalProperties.Schema)
		}
		for _, list := range []openapi3.SchemaRefs{s.AllOf, s.AnyOf, s.OneOf} {
			for _, r := range list {
				walk(r)
			}
		}
	}
	for _, ref := range spec.Components.Schemas {
		walk(ref)
	}
	for _, item := range spec.Paths.Map() {
		for _, op := range item.Operations() {
			for _, p := range append(item.Parameters, op.Parameters...) {
				if p.Value != nil {
					walk(p.Value.Schema)
				}
			}
			if op.RequestBody != nil && op.RequestBody.Value != nil {
				for _, mt := range op.RequestBody.Value.Content {
					walk(mt.Schema)
				}
			}
		}
	}
}
