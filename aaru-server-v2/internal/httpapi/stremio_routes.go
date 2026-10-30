package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/stremio"
	"bytes"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/labstack/echo/v4"
)

// StremioRoutes.swift: SCR-003's HTTP surface, hand-written because the Stremio protocol fixes the
// paths. Every answer carries `Access-Control-Allow-Origin: *` (Stremio Web fetches from the browser),
// errors included. The token in the path is a bearer secret: it is never logged (middleware.Redacted),
// and a revoked one gets a 404 manifest and empty catalogs.

func (s *Server) registerStremioRoutes(e *echo.Echo) {
	e.GET("/stremio/*", s.stremioRespond)
	e.OPTIONS("/stremio/*", func(c echo.Context) error {
		stremioHeaders(c, 86400)
		return c.NoContent(http.StatusNoContent)
	})
}

func stremioHeaders(c echo.Context, maxAge int) {
	h := c.Response().Header()
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Allow-Headers", "*")
	h.Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	// Private: every answer is one user's library.
	if maxAge > 0 {
		h.Set("Cache-Control", "private, max-age="+strconv.Itoa(maxAge))
	} else {
		h.Set("Cache-Control", "no-store")
	}
}

// stremioJSON writes body as Swift's encoder did: sorted keys (struct order), slashes unescaped.
func stremioJSON(c echo.Context, status int, body any, maxAge int) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	data := []byte("{}")
	if err := enc.Encode(body); err == nil {
		data = bytes.TrimRight(buf.Bytes(), "\n")
	}
	stremioHeaders(c, maxAge)
	c.Response().Header().Set("Content-Type", "application/json; charset=utf-8")
	c.Response().WriteHeader(status)
	_, err := c.Response().Write(data)
	return err
}

func stremioFail(c echo.Context, status int, message string) error {
	return stremioJSON(c, status, stremio.Err(message), 0)
}

func (s *Server) stremioRespond(c echo.Context) error {
	parsed, ok := stremio.ParseRequest(c.Request().URL.EscapedPath())
	if !ok {
		return stremioFail(c, http.StatusNotFound, "Not a Stremio addon path.")
	}
	ctx := c.Request().Context()
	caller, found, err := s.AgentTokens.Authenticate(ctx, parsed.Token, auth.GroupStremio)
	if err == nil && found && !s.AgentTokens.Allow(caller) {
		return stremioFail(c, http.StatusTooManyRequests, "Too many requests.")
	}
	var callerPtr *auth.AgentCaller
	if found {
		callerPtr = &caller
	}
	if err == nil {
		var done bool
		done, err = s.stremioAnswer(c, parsed, callerPtr)
		if done {
			return err
		}
	}
	s.Log.ErrorContext(ctx, "Stremio request failed", "error", err.Error())
	return stremioFail(c, http.StatusInternalServerError, "Something went wrong.")
}

// stremioAnswer answers the request; done is false when a service call failed and nothing was written.
func (s *Server) stremioAnswer(c echo.Context, r stremio.Request, caller *auth.AgentCaller) (bool, error) {
	switch r.Kind {
	case stremio.RouteManifest:
		if caller == nil {
			return true, stremioFail(c, http.StatusNotFound,
				"This Aaru link was revoked. Connect Stremio again in Aaru's Settings.")
		}
		return true, stremioJSON(c, http.StatusOK, stremio.TheManifest, 3600)
	case stremio.RouteConfigure:
		h := c.Response().Header()
		h.Set("Location", stremio.ConfigureURL)
		h.Set("Access-Control-Allow-Origin", "*")
		return true, c.NoContent(http.StatusFound)
	default:
		return s.stremioResource(c, r, caller)
	}
}

func (s *Server) stremioResource(c echo.Context, r stremio.Request, caller *auth.AgentCaller) (bool, error) {
	ctx := c.Request().Context()
	switch r.Name {
	case "catalog":
		// A revoked or unknown token sees empty catalogs rather than an error.
		metas := []stremio.MetaPreview{}
		if caller != nil {
			var err error
			if metas, err = s.Stremio.CatalogRows(ctx, r.ID, r.Type, r.Extra, *caller); err != nil {
				return false, err
			}
		}
		return true, stremioJSON(c, http.StatusOK, stremio.CatalogResponse{Metas: metas}, 60)
	case "meta":
		if caller == nil {
			return true, stremioFail(c, http.StatusNotFound, "Unknown title.")
		}
		meta, err := s.Stremio.Meta(ctx, r.ID, *caller)
		if err != nil {
			return false, err
		}
		if meta == nil {
			return true, stremioFail(c, http.StatusNotFound, "Unknown title.")
		}
		return true, stremioJSON(c, http.StatusOK, stremio.MetaResponse{Meta: *meta}, 3600)
	case "player", "library":
		if caller == nil {
			return true, stremioFail(c, http.StatusNotFound, "This Aaru link was revoked.")
		}
		var result stremio.EventResult
		var err error
		if r.Name == "player" {
			result, err = s.Stremio.Player(ctx, r.Type, r.ID, r.Extra, *caller)
		} else {
			result, err = s.Stremio.LibraryEvent(ctx, r.Type, r.ID, r.Extra, *caller)
		}
		if err != nil {
			return false, err
		}
		if result == stremio.Forbidden {
			return true, stremioFail(c, http.StatusForbidden, "This link may not do that.")
		}
		return true, stremioJSON(c, http.StatusOK, stremio.Message{}, 0)
	default:
		// `stream` and `subtitles` included: Aaru serves neither.
		return true, stremioFail(c, http.StatusNotFound, "Not supported.")
	}
}
