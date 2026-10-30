package middleware

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/provider"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/labstack/echo/v4"
)

// Reporter sends a server failure somewhere (Sentry). Nothing from the request goes with it.
type Reporter interface {
	Report(f Failure)
}

// Failure is what a 5xx report carries.
type Failure struct {
	ErrorType string
	Code      string
	Status    int
	Method    string
	Route     string
	// Operation is the openapi operation id, when a generated handler failed.
	Operation string
	// Provider names the outside service whose failure this was.
	Provider string
}

// Errors turns every error into the shared ErrorResponse JSON. Unknown errors
// become an opaque 500 and are logged; their text never reaches the client.
func Errors(log *slog.Logger, reporter Reporter) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			err := next(c)
			if err == nil {
				return nil
			}
			if c.Response().Committed {
				log.Error("Request failed after the response started", "errorType", errorType(err))
				return nil
			}
			appErr := Map(err)
			if appErr.Status >= 500 {
				route := RouteTemplate(c)
				if route == "" {
					route = "unmatched"
				}
				f := Failure{
					ErrorType: errorType(err), Code: appErr.Code, Status: appErr.Status,
					Method: c.Request().Method, Route: route, Operation: operation(c),
				}
				attrs := []any{"code", appErr.Code, "errorType", f.ErrorType, "error", err.Error(), "route", route}
				if f.Operation != "" {
					attrs = append(attrs, "operation", f.Operation)
				}
				var providerErr *provider.Error
				if errors.As(err, &providerErr) {
					f.Provider = providerErr.Provider
					attrs = append(attrs, "provider", providerErr.Provider, "providerFailure", providerFailure(providerErr))
				}
				log.Error("Request failed", attrs...)
				if reporter != nil {
					reporter.Report(f)
				}
			}
			if appErr.Status == http.StatusNotFound && c.Path() == "" {
				c.Set(unmatchedKey, true)
			}
			return Write(c, appErr)
		}
	}
}

// Map finds the route error in err; framework errors map to the shared codes.
func Map(err error) *apperr.Error {
	if e := apperr.From(err); e != nil {
		return e
	}
	var httpErr *echo.HTTPError
	if errors.As(err, &httpErr) {
		switch {
		case httpErr.Code == http.StatusBadRequest:
			return apperr.BadRequest()
		case httpErr.Code >= 500:
			return apperr.Internal()
		default:
			return apperr.FromStatus(httpErr.Code, http.StatusText(httpErr.Code))
		}
	}
	return apperr.Internal()
}

type body struct {
	Code    string            `json:"code"`
	Details map[string]string `json:"details,omitempty"`
	Message string            `json:"message"`
}

// Write sends e in the shared shape.
func Write(c echo.Context, e *apperr.Error) error {
	data, err := json.Marshal(body{Code: e.Code, Details: e.Details, Message: e.Message})
	if err != nil {
		data = []byte(`{"code":"internal","message":"Something went wrong."}`)
	}
	return c.Blob(e.Status, "application/json; charset=utf-8", data)
}

func errorType(err error) string {
	for {
		next := errors.Unwrap(err)
		if next == nil {
			break
		}
		err = next
	}
	t := "error"
	if err != nil {
		t = typeName(err)
	}
	return t
}

// providerFailure is Swift's "\(provider.kind)": refused carries its status.
func providerFailure(e *provider.Error) string {
	if e.Kind == provider.KindRefused {
		return fmt.Sprintf("refused(%d)", e.Status)
	}
	return e.Kind.String()
}
