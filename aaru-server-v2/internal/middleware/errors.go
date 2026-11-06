package middleware

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v5"
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

// StatusClientClosedRequest is nginx's 499: the client went away before the answer. Logs and
// metrics use it; nobody is left to read it.
const StatusClientClosedRequest = 499

const reporterKey = "aaru.reporter"

// Errors turns every error into the shared ErrorResponse JSON. Unknown errors
// become an opaque 500 and are logged; their text never reaches the client. A
// request the client gave up on is not a failure (HTTP-002): it is logged at Info
// as a 499 and never reported.
func Errors(log *slog.Logger, reporter Reporter) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c *echo.Context) error {
			if reporter != nil {
				c.Set(reporterKey, reporter)
			}
			// The context as it arrived: inner middleware (Deadline) derive and cancel their own.
			ctx := c.Request().Context()
			err := next(c)
			if err == nil {
				return nil
			}
			if Committed(c) {
				// A response under way (a streamed export) cannot take an error body. A client
				// that left is not a failure; anything else is one nobody else will report.
				if ClientGone(ctx, err) {
					return nil
				}
				log.ErrorContext(ctx, "Request failed after the response started", "errorType", errorType(err))
				if reporter != nil {
					f, _ := failure(c, err, "internal", http.StatusInternalServerError)
					reporter.Report(f)
				}
				return nil
			}
			if ClientGone(ctx, err) {
				log.InfoContext(ctx, "Request cancelled by the client", "route", routeLabel(c), "errorType", errorType(err))
				c.Response().WriteHeader(StatusClientClosedRequest)
				return nil
			}
			appErr := Map(err)
			if appErr.Status >= 500 {
				f, attrs := failure(c, err, appErr.Code, appErr.Status)
				log.ErrorContext(ctx, "Request failed", attrs...)
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

// ClientGone reports an error that is only the client going away: err is a cancellation and
// the request's own context is done.
func ClientGone(ctx context.Context, err error) bool {
	return errors.Is(err, context.Canceled) && ctx.Err() != nil
}

// ReportFailure sends a 5xx that a transport answered itself (MCP, scrobbles, ListenBrainz,
// Stremio, OAuth write their own bodies) to the reporter Errors holds, as Errors would have
// (HTTP-006). The transport logs it; a client that went away is not reported.
func ReportFailure(c *echo.Context, err error, code string, status int) {
	reporter, _ := c.Get(reporterKey).(Reporter)
	if reporter == nil || err == nil || ClientGone(c.Request().Context(), err) {
		return
	}
	f, _ := failure(c, err, code, status)
	reporter.Report(f)
}

func routeLabel(c *echo.Context) string {
	if route := RouteTemplate(c); route != "" {
		return route
	}
	return "unmatched"
}

// failure is the report for err and the attributes its log line carries.
func failure(c *echo.Context, err error, code string, status int) (Failure, []any) {
	route := routeLabel(c)
	f := Failure{
		ErrorType: errorType(err), Code: code, Status: status,
		Method: MethodLabel(c.Request().Method), Route: route, Operation: operation(c),
	}
	attrs := []any{"code", code, "errorType", f.ErrorType, "error", err.Error(), "route", route}
	if f.Operation != "" {
		attrs = append(attrs, "operation", f.Operation)
	}
	var providerErr *provider.Error
	if errors.As(err, &providerErr) {
		f.Provider = providerErr.Provider
		attrs = append(attrs, "provider", providerErr.Provider, "providerFailure", providerFailure(providerErr))
	}
	var panicErr *PanicError
	if errors.As(err, &panicErr) {
		attrs = append(attrs, "stack", string(panicErr.Stack))
	}
	return f, attrs
}

// sqlStateQueryCanceled is Postgres' query_canceled, what statement_timeout raises.
const sqlStateQueryCanceled = "57014"

// errTimeout is a request that ran out of time: its deadline, a pool that had no free
// connection within POSTGRES_POOL_TIMEOUT, or Postgres' statement_timeout (DB-001).
func errTimeout() *apperr.Error {
	return apperr.Unavailable("timeout", "Aaru is busy right now. Try again in a moment.")
}

// Map finds the route error in err; framework errors map to the shared codes.
func Map(err error) *apperr.Error {
	if e := apperr.From(err); e != nil {
		return e
	}
	// echo v5's own 404 and 405 are sentinels, not *HTTPError: StatusCode reads both.
	if code := echo.StatusCode(err); code != 0 {
		switch {
		case code == http.StatusBadRequest:
			return apperr.BadRequest()
		case code >= 500:
			return apperr.Internal()
		default:
			return apperr.FromStatus(code, http.StatusText(code))
		}
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return errTimeout()
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == sqlStateQueryCanceled {
		return errTimeout()
	}
	return apperr.Internal()
}

type body struct {
	Code    string            `json:"code"`
	Details map[string]string `json:"details,omitempty"`
	Message string            `json:"message"`
}

// Write sends e in the shared shape.
func Write(c *echo.Context, e *apperr.Error) error {
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
