package httpapi

import (
	"aaru-go-api/internal/oauth"
	"aaru-go-api/internal/reqctx"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"unicode/utf8"

	"github.com/labstack/echo/v4"
)

// oauthBodyLimit is what the registration, token and revoke endpoints read.
const oauthBodyLimit = 16 * 1024

// errOAuthBodyTooLarge is a body over the limit. Like the Swift server's
// `collect(upTo:)` failure it is not an OAuth error, so it answers `server_error`.
var errOAuthBodyTooLarge = errors.New("oauth body over 16 KB")

var oauthCORS = map[string]string{
	"Access-Control-Allow-Origin":  "*",
	"Access-Control-Allow-Headers": "Authorization, Content-Type, MCP-Protocol-Version",
	"Access-Control-Allow-Methods": "GET, POST, OPTIONS",
	"Access-Control-Max-Age":       "86400",
}

// registerOAuthRoutes adds OUT-004's endpoints and discovery documents. Their
// shapes are fixed by RFC 8414, 9728, 7591, 6749 and 7009, not by openapi.yaml.
// claude.ai reads discovery and exchanges tokens from the browser, so these
// answer CORS `*` without credentials. The user's own decision goes through
// `/v1/oauth/requests`.
func (s *Server) registerOAuthRoutes(e *echo.Echo) {
	if s.OAuth == nil {
		return
	}
	for _, path := range []string{"/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/v1/mcp"} {
		e.GET(path, func(c echo.Context) error { return oauthJSON(c, http.StatusOK, s.OAuth.ProtectedResource()) })
	}
	e.GET("/.well-known/oauth-authorization-server", func(c echo.Context) error {
		return oauthJSON(c, http.StatusOK, s.OAuth.AuthorizationServer())
	})
	e.POST("/oauth/register", s.oauthRespond(s.oauthRegister))
	e.GET("/oauth/authorize", s.oauthRespond(s.oauthAuthorize))
	e.POST("/oauth/token", s.oauthRespond(func(c echo.Context) error {
		form, err := oauthForm(c)
		if err != nil {
			return err
		}
		body, err := s.OAuth.Token(c.Request().Context(), form)
		if err != nil {
			return err
		}
		return oauthJSON(c, http.StatusOK, body)
	}))
	e.POST("/oauth/revoke", s.oauthRespond(func(c echo.Context) error {
		form, err := oauthForm(c)
		if err != nil {
			return err
		}
		if err := s.OAuth.Revoke(c.Request().Context(), form); err != nil {
			return err
		}
		return oauthJSON(c, http.StatusOK, map[string]any{})
	}))
	for _, path := range []string{
		"/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/v1/mcp",
		"/.well-known/oauth-authorization-server", "/oauth/register", "/oauth/token", "/oauth/revoke",
	} {
		e.OPTIONS(path, func(c echo.Context) error {
			for k, v := range oauthCORS {
				c.Response().Header().Set(k, v)
			}
			return c.NoContent(http.StatusNoContent)
		})
	}
}

func (s *Server) oauthRegister(c echo.Context) error {
	body, err := readLimited(c.Request().Body, oauthBodyLimit)
	if err != nil {
		return err
	}
	var registration oauth.Registration
	if trimmed := bytes.TrimSpace(body); !bytes.HasPrefix(trimmed, []byte("{")) || json.Unmarshal(body, &registration) != nil {
		return &oauth.Error{Status: http.StatusBadRequest, Code: "invalid_client_metadata", Description: "The body is not JSON client metadata."}
	}
	client, err := s.OAuth.Register(c.Request().Context(), registration, reqctx.ClientAddress(c.Request().Context()))
	if err != nil {
		return err
	}
	return oauthJSON(c, http.StatusCreated, client)
}

func (s *Server) oauthAuthorize(c echo.Context) error {
	query := map[string]string{}
	for name, values := range c.Request().URL.Query() {
		if len(values) > 0 {
			query[name] = values[len(values)-1]
		}
	}
	answer, err := s.OAuth.Authorize(c.Request().Context(), query)
	if err != nil {
		return err
	}
	h := c.Response().Header()
	h.Set("Cache-Control", "no-store")
	switch {
	case answer.Refuse != "":
		return c.Blob(http.StatusBadRequest, "text/plain; charset=utf-8", []byte(answer.Refuse))
	case answer.Redirect != "":
		h.Set("Location", answer.Redirect)
	default:
		h.Set("Location", answer.Consent)
		h.Set("Set-Cookie", s.OAuth.BindingCookie(answer.Binding))
	}
	return c.NoContent(http.StatusFound)
}

// oauthRespond answers every OAuth failure as RFC 6749's JSON; anything
// unexpected is logged and stays vague.
func (s *Server) oauthRespond(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		err := next(c)
		if err == nil {
			return nil
		}
		var oauthErr *oauth.Error
		if errors.As(err, &oauthErr) {
			return oauthJSON(c, oauthErr.Status, map[string]any{"error": oauthErr.Code, "error_description": oauthErr.Description})
		}
		s.Log.Error("OAuth request failed", "error", err.Error())
		return oauthJSON(c, http.StatusInternalServerError, map[string]any{"error": "server_error", "error_description": "Try again later."})
	}
}

// oauthJSON writes body with sorted keys and unescaped slashes, plus CORS and no-store.
func oauthJSON(c echo.Context, status int, body map[string]any) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	data := []byte("{}")
	if enc.Encode(body) == nil {
		data = bytes.TrimSuffix(buf.Bytes(), []byte("\n"))
	}
	h := c.Response().Header()
	for k, v := range oauthCORS {
		h.Set(k, v)
	}
	h.Set("Cache-Control", "no-store")
	return c.Blob(status, "application/json", data)
}

func readLimited(r io.Reader, limit int64) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > limit {
		return nil, errOAuthBodyTooLarge
	}
	return data, nil
}

// oauthForm is an `application/x-www-form-urlencoded` body, read as the Swift
// server did: `+` is a space, a bad escape keeps its raw text, the last field wins.
func oauthForm(c echo.Context) (map[string]string, error) {
	body, err := readLimited(c.Request().Body, oauthBodyLimit)
	if err != nil {
		return nil, err
	}
	fields := map[string]string{}
	for _, pair := range strings.Split(string(body), "&") {
		if pair == "" {
			continue
		}
		name, value, hasValue := strings.Cut(pair, "=")
		name = formDecode(name)
		if name == "" {
			continue
		}
		if hasValue {
			fields[name] = formDecode(value)
		} else {
			fields[name] = ""
		}
	}
	return fields, nil
}

func formDecode(s string) string {
	spaced := strings.ReplaceAll(s, "+", " ")
	decoded, err := url.PathUnescape(spaced)
	if err != nil || !utf8.ValidString(decoded) {
		return s
	}
	return decoded
}
