package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/middleware"
	"aaru-go-api/internal/music"
	"aaru-go-api/internal/scrobble"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"unicode"

	"github.com/labstack/echo/v4"
)

// ScrobbleRoutes.swift: SCR-001's HTTP surface, first used by the browser extension (SCR-007):
// `POST /v1/scrobble/start|pause|stop`. Hand-written like the MCP and Stremio routes because it
// authenticates itself: only a scrobble token (`aaru_scr_…`) gets in, never a session, an MCP token or
// a Stremio link. The body is Trakt's scrobble shape plus `source` and `ref`.

const (
	scrobblePath    = "/v1/scrobble"
	scrobbleMaxBody = 16 * 1024
)

func (s *Server) registerScrobbleRoutes(e *echo.Echo) {
	for _, action := range []scrobble.Action{scrobble.ActionStart, scrobble.ActionPause, scrobble.ActionStop} {
		e.POST(scrobblePath+"/"+string(action), func(c echo.Context) error { return s.scrobbleRespond(c, action) })
	}
}

// writeJSON writes v as Swift's encoder did here: sorted keys, slashes unescaped, `no-store`.
func writeJSON(c echo.Context, status int, v any) error {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return err
	}
	h := c.Response().Header()
	h.Set("Content-Type", "application/json")
	h.Set("Cache-Control", "no-store")
	c.Response().WriteHeader(status)
	_, err := c.Response().Write(bytes.TrimRight(buf.Bytes(), "\n"))
	return err
}

// scrobbleError is `/v1`'s one error shape.
func scrobbleError(c echo.Context, status int, code, message string) error {
	return writeJSON(c, status, map[string]string{"code": code, "message": message})
}

// readUpTo reads at most limit bytes; false when the body is longer.
func readUpTo(body io.Reader, limit int64) ([]byte, bool, error) {
	data, err := io.ReadAll(io.LimitReader(body, limit+1))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			return nil, false, nil
		}
		return nil, false, err
	}
	return data, int64(len(data)) <= limit, nil
}

func (s *Server) scrobbleRespond(c echo.Context, action scrobble.Action) error {
	ctx := c.Request().Context()
	err := func() error {
		secret := middleware.BearerToken(c.Request().Header.Get("Authorization"))
		var caller auth.AgentCaller
		ok := false
		if secret != "" {
			var err error
			if caller, ok, err = s.AgentTokens.Authenticate(ctx, secret, auth.GroupScrobble); err != nil {
				return err
			}
		}
		if !ok {
			c.Response().Header().Set("WWW-Authenticate", `Bearer realm="aaru"`)
			return scrobbleError(c, http.StatusUnauthorized, "unauthorized", "Connect the extension in Aaru again.")
		}
		if !caller.Has(auth.ScopeScrobbleWrite) {
			return scrobbleError(c, http.StatusForbidden, "forbidden", "This connection may not scrobble.")
		}
		if !s.AgentTokens.Allow(caller) {
			return scrobbleError(c, http.StatusTooManyRequests, "rate_limited", "Too many requests. Wait a minute.")
		}
		data, fits, err := readUpTo(c.Request().Body, scrobbleMaxBody)
		if err != nil {
			return err
		}
		if !fits {
			return scrobbleError(c, http.StatusRequestEntityTooLarge, "validation_failed", "A scrobble is at most 16 KiB.")
		}
		answer, err := s.scrobbleAnswer(c, data, action, caller)
		var bad *scrobble.InvalidError
		if errors.As(err, &bad) {
			return scrobbleError(c, http.StatusUnprocessableEntity, "validation_failed", bad.Message)
		}
		if err != nil {
			return err
		}
		return writeJSON(c, http.StatusOK, answer)
	}()
	if err != nil {
		s.Log.ErrorContext(ctx, "Scrobble failed", "error", err.Error())
		return scrobbleError(c, http.StatusInternalServerError, "internal", "Something went wrong.")
	}
	return nil
}

func (s *Server) scrobbleAnswer(c echo.Context, data []byte, action scrobble.Action, caller auth.AgentCaller) (scrobble.Answer, error) {
	ctx := c.Request().Context()
	body, err := scrobble.ParseBody(data)
	if err != nil {
		return scrobble.Answer{}, err
	}
	if body.Video != nil {
		return s.scrobbleVideo(c, body, action, caller)
	}
	report, err := body.Report(action)
	if err != nil {
		return scrobble.Answer{}, err
	}
	outcome, title, err := s.Scrobble.Record(ctx, report, caller)
	if err != nil {
		return scrobble.Answer{}, err
	}
	return scrobble.NewAnswer(outcome, title), nil
}

// scrobbleVideo is a YouTube video (SCR-009): a play, never a watch event, so it matches and ticks
// nothing. A music video heard long enough is also a listen (SCR-011).
func (s *Server) scrobbleVideo(c echo.Context, body scrobble.Body, action scrobble.Action, caller auth.AgentCaller) (scrobble.Answer, error) {
	ctx := c.Request().Context()
	now := s.Scrobble.NowTime()
	video, err := body.VideoPlay(action, now)
	if err != nil {
		return scrobble.Answer{}, err
	}
	listen, err := body.VideoListen(now)
	if err != nil {
		return scrobble.Answer{}, err
	}
	if listen != nil {
		if err := s.Scrobble.Heard(ctx, *listen, caller); err != nil {
			return scrobble.Answer{}, err
		}
	}
	if action == scrobble.ActionStop {
		if err := s.Scrobble.StopPlay(ctx, scrobble.PlayVideo, caller); err != nil {
			return scrobble.Answer{}, err
		}
		return scrobble.NewAnswer(scrobble.StoppedWithoutChange, nil), nil
	}
	if err := s.Scrobble.Play(ctx, video, caller); err != nil {
		return scrobble.Answer{}, err
	}
	return scrobble.NewAnswer(scrobble.Recorded, nil), nil
}

// MARK: ListenBrainz (MUS-005)

// ListenBrainzRoutes.swift: ListenBrainz's submit API, so scrobblers that let you set a ListenBrainz
// server (Web Scrobbler, Pano Scrobbler, Navidrome, Jellyfin's plugin, Multi-Scrobbler) send listens
// to Aaru. Outside `/v1` like Stremio's routes, because it speaks ListenBrainz's shapes:
// `Authorization: Token …`, `{listen_type, payload}`, and `{code, error}` errors. Only a music token
// (`aaru_lb_…`) gets in.

// listenBrainzPath is in agent_setup.go.
const (
	// listenBrainzMaxBody is ListenBrainz's own limit: 10 MB a request.
	listenBrainzMaxBody = 10 * 1024 * 1024
)

func (s *Server) registerListenBrainzRoutes(e *echo.Echo) {
	e.POST(listenBrainzPath+"/submit-listens", s.listenBrainzSubmit)
	e.GET(listenBrainzPath+"/validate-token", s.listenBrainzValidate)
	// Browser scrobblers fetch from a page or an extension; nothing here reads a cookie.
	for _, path := range []string{"submit-listens", "validate-token"} {
		e.OPTIONS(listenBrainzPath+"/"+path, func(c echo.Context) error {
			listenBrainzCORS(c)
			return c.NoContent(http.StatusNoContent)
		})
	}
}

func listenBrainzCORS(c echo.Context) {
	h := c.Response().Header()
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
	h.Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	h.Set("Access-Control-Max-Age", "86400")
}

func listenBrainzJSON(c echo.Context, status int, v any) error {
	listenBrainzCORS(c)
	return writeJSON(c, status, v)
}

// listenBrainzFailure is ListenBrainz's error shape.
type listenBrainzFailure struct {
	Code  int    `json:"code"`
	Error string `json:"error"`
}

func listenBrainzError(c echo.Context, status int, message string) error {
	return listenBrainzJSON(c, status, listenBrainzFailure{Code: status, Error: message})
}

// listenBrainzToken is `Authorization: Token …` as ListenBrainz documents it, or `Bearer …`.
func listenBrainzToken(header string) string {
	scheme, rest, ok := cutSpace(header)
	if !ok {
		return ""
	}
	switch scheme {
	case "token", "bearer":
		return trimSpaces(rest)
	}
	return ""
}

func (s *Server) listenBrainzSubmit(c echo.Context) error {
	ctx := c.Request().Context()
	err := func() error {
		var caller auth.AgentCaller
		ok := false
		if secret := listenBrainzToken(c.Request().Header.Get("Authorization")); secret != "" {
			var err error
			if caller, ok, err = s.AgentTokens.Authenticate(ctx, secret, auth.GroupMusic); err != nil {
				return err
			}
		}
		if !ok {
			return listenBrainzError(c, http.StatusUnauthorized, "Invalid authorization token. Connect the scrobbler in Aaru again.")
		}
		if !caller.Has(auth.ScopeScrobbleWrite) {
			return listenBrainzError(c, http.StatusForbidden, "This connection may not send listens.")
		}
		if !s.AgentTokens.Allow(caller) {
			return listenBrainzError(c, http.StatusTooManyRequests, "Too many requests. Wait a minute.")
		}
		data, fits, err := readUpTo(c.Request().Body, listenBrainzMaxBody)
		if err != nil {
			return err
		}
		if !fits {
			return listenBrainzError(c, http.StatusRequestEntityTooLarge, "A submission is at most 10 MB.")
		}
		now := s.Scrobble.NowTime()
		submission, err := music.ParseSubmission(data, now)
		var bad *music.InvalidError
		if errors.As(err, &bad) {
			return listenBrainzError(c, http.StatusBadRequest, bad.Message)
		}
		if err != nil {
			return err
		}
		if len(submission.Listens) > 0 {
			if _, err := s.Listens.Submit(ctx, submission.Listens, caller); err != nil {
				return err
			}
		}
		if submission.PlayingNow != nil {
			if err := s.Scrobble.Play(ctx, scrobble.TrackPlay(*submission.PlayingNow, now), caller); err != nil {
				return err
			}
		}
		return listenBrainzJSON(c, http.StatusOK, map[string]string{"status": "ok"})
	}()
	if err != nil {
		s.Log.ErrorContext(ctx, "Listen submission failed", "error", err.Error())
		return listenBrainzError(c, http.StatusInternalServerError, "Something went wrong.")
	}
	return nil
}

// listenBrainzTokenCheck is validate-token's answer.
type listenBrainzTokenCheck struct {
	Code     int     `json:"code"`
	Message  string  `json:"message"`
	Valid    bool    `json:"valid"`
	UserName *string `json:"user_name,omitempty"`
}

// listenBrainzValidate answers 200 either way and says in `valid` whether the token works.
func (s *Server) listenBrainzValidate(c echo.Context) error {
	ctx := c.Request().Context()
	secret := listenBrainzToken(c.Request().Header.Get("Authorization"))
	if secret == "" {
		secret = c.QueryParam("token")
	}
	if secret == "" {
		return listenBrainzError(c, http.StatusBadRequest, "You need to provide an Authorization token.")
	}
	caller, ok, err := s.AgentTokens.Authenticate(ctx, secret, auth.GroupMusic)
	if err != nil {
		s.Log.ErrorContext(ctx, "Token check failed", "error", err.Error())
		return listenBrainzError(c, http.StatusInternalServerError, "Something went wrong.")
	}
	if !ok {
		return listenBrainzJSON(c, http.StatusOK, listenBrainzTokenCheck{Code: 200, Message: "Token invalid."})
	}
	// Clients show this as the account they are signed in to; the token's name says which.
	name := caller.Token.Name
	return listenBrainzJSON(c, http.StatusOK, listenBrainzTokenCheck{
		Code: 200, Message: "Token valid.", Valid: true, UserName: &name,
	})
}

// cutSpace splits "Scheme rest" at the first space, the scheme lowercased.
func cutSpace(header string) (scheme, rest string, ok bool) {
	scheme, rest, ok = strings.Cut(strings.TrimLeft(header, " "), " ")
	return strings.ToLower(scheme), rest, ok
}

// trimSpaces trims spaces and tabs (`.whitespaces`), not newlines.
func trimSpaces(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return r == '\t' || unicode.Is(unicode.Zs, r) })
}
