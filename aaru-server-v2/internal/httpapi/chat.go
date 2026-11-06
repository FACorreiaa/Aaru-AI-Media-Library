package httpapi

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apiid"
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/middleware"
	"aaru-go-api/internal/safe"
	"aaru-go-api/internal/telemetry"
	"aaru-go-api/internal/transcription"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/labstack/echo/v5"
)

const (
	// maxChatBody is the most a Chat turn may say, in characters, once trimmed.
	maxChatBody = 4000
	// chatHeartbeatEvery keeps a quiet stream open through Traefik and Cloudflare.
	chatHeartbeatEvery = 15 * time.Second
	// maxChatAudioBytes and maxChatAudioSeconds bound one spoken question, held in memory only.
	maxChatAudioBytes   = 8 << 20
	maxChatAudioSeconds = 60
	// transcriptionsPerHour is each user's share of a CPU-only service.
	transcriptionsPerHour = 40
	// maxTranscriptionsInFlight keeps parallel 8 MB uploads off the pod's memory limit and off the
	// CPU-only service. Per process, held across the body read and the service call.
	maxTranscriptionsInFlight = 4
	// maxVocabularyTitles is how many titles bias a transcription toward what the user watches.
	maxVocabularyTitles = 30
)

var (
	errChatNotFound       = apperr.NotFound("That chat doesn't exist.")
	errChatBusy           = apperr.New(http.StatusConflict, "chat_busy", "Aaru is still answering in this chat.")
	errAgentUnavailable   = apperr.Unavailable("agent_unavailable", "Aaru isn't available right now.")
	errChatBlank          = apperr.Validation("body", "Ask Aaru something first.")
	errChatTooLong        = apperr.Validation("body", "That is longer than Aaru reads. Keep it to 4,000 characters or fewer.")
	errVoiceUnavailable   = apperr.Unavailable("transcription_unavailable", "Voice isn't available right now.")
	errAudioTooLarge      = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That recording is larger than 8 MB.")
	errAudioTooLong       = apperr.New(http.StatusRequestEntityTooLarge, "audio_too_long", "That recording is longer than 60 seconds.")
	errTranscriptionEmpty = apperr.New(http.StatusUnprocessableEntity, "transcription_empty", "Aaru didn't hear any words.")
	errTooManyVoice       = apperr.RateLimited("Too many spoken questions. Try again later.")
	errAttachmentGone     = apperr.New(http.StatusUnprocessableEntity, "attachment_gone",
		"That file is no longer here. Files are kept for an hour; attach it again.")
	errTooManyTurnFiles = apperr.Validation("attachments", "Send up to 5 files at a time.")
	errVoiceBusy        = apperr.RateLimited("Voice is busy right now. Try again in a moment.")
)

func (s *Server) chats() *agent.ChatStore { return &agent.ChatStore{Q: s.q} }

// CreateChat is POST /v1/chats.
func (s *Server) CreateChat(ctx context.Context, _ api.CreateChatRequestObject) (api.CreateChatResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	id, err := s.chats().CreateChat(ctx, user)
	if err != nil {
		return nil, err
	}
	return api.CreateChat201JSONResponse{Id: apiid.From(id)}, nil
}

// DeleteChats is DELETE /v1/chats: every chat of the caller, turns with them.
func (s *Server) DeleteChats(ctx context.Context, _ api.DeleteChatsRequestObject) (api.DeleteChatsResponseObject, error) {
	user, err := currentUser(ctx)
	if err != nil {
		return nil, err
	}
	if err := s.chats().DeleteAll(ctx, user); err != nil {
		return nil, err
	}
	return api.DeleteChats204Response{}, nil
}

// GetChatStatus is GET /v1/chats/status.
func (s *Server) GetChatStatus(ctx context.Context, _ api.GetChatStatusRequestObject) (api.GetChatStatusResponseObject, error) {
	if _, err := currentUser(ctx); err != nil {
		return nil, err
	}
	return api.GetChatStatus200JSONResponse{Assistant: s.Model != nil, Voice: s.Transcription != nil}, nil
}

// chatTurn is `POST /v1/chats/{id}/turns`: the answer as server-sent events. The headers go out with
// the first frame, so whatever Turn refuses before that is still a JSON error. Turn returns an error
// only when it has emitted nothing; after that a failure is an `error` frame.
func (s *Server) chatTurn(c *echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	if s.Model == nil {
		return errAgentUnavailable
	}
	chat, err := uuid.Parse(c.Param("id"))
	if err != nil {
		return errChatNotFound
	}
	ask, err := readChatTurn(c)
	if err != nil {
		return err
	}
	stream := &chatStream{res: middleware.Response(c), log: s.Log, every: s.chatHeartbeat, stop: make(chan struct{})}
	defer stream.close()
	err = s.chatService().Turn(ctx, user, chat, ask, stream.send)
	switch {
	case errors.Is(err, agent.ErrChatNotFound):
		return errChatNotFound
	case errors.Is(err, agent.ErrAttachmentGone):
		return errAttachmentGone
	case errors.Is(err, agent.ErrChatBusy):
		return errChatBusy
	case err != nil:
		return err
	}
	telemetry.Capture(telemetry.AssistantTurn, user, nil)
	return nil
}

// readChatTurn is the request's words, trimmed, its hint and its files. A raw route is not in the
// embedded spec, so no validator has seen this body; the length is checked after trimming, or blank
// would pass. Blank is allowed when the turn carries files (ASK-010).
func readChatTurn(c *echo.Context) (agent.Ask, error) {
	if contentType(c) != "application/json" {
		return agent.Ask{}, errUnreadable
	}
	data, fits, err := readUpTo(c.Request().Body, defaultBodyLimit)
	if err != nil || !fits {
		return agent.Ask{}, apperr.BadRequest()
	}
	var req api.ChatTurnRequest
	if err := json.Unmarshal(data, &req); err != nil {
		return agent.Ask{}, apperr.BadRequest()
	}
	body := strings.TrimSpace(req.Body)
	var files []uuid.UUID
	if req.Attachments != nil {
		for _, id := range *req.Attachments {
			files = append(files, id.ID())
		}
	}
	switch {
	case len(files) > agent.MaxTurnAttachments:
		return agent.Ask{}, errTooManyTurnFiles
	case body == "" && len(files) == 0:
		return agent.Ask{}, errChatBlank
	case utf8.RuneCountInString(body) > maxChatBody:
		return agent.Ask{}, errChatTooLong
	case strings.ContainsRune(body, 0):
		// Postgres text cannot hold it, and nobody types it.
		return agent.Ask{}, apperr.BadRequest()
	}
	var hint agent.Hint
	if req.Hint != nil {
		hint.Screen = req.Hint.Screen
		if req.Hint.TitleId != nil {
			// A malformed id reads as the nil id, which the catalog does not have: dropped.
			title := req.Hint.TitleId.ID()
			hint.TitleID = &title
		}
	}
	return agent.Ask{Body: body, Hint: hint, Attachments: files}, nil
}

// chatStream writes a Chat turn's events as they come, flushing each. The heartbeat starts with the
// first frame: before it, nothing is committed and the route can still answer in JSON.
type chatStream struct {
	res   *echo.Response
	log   *slog.Logger
	every time.Duration
	stop  chan struct{}
	beats sync.WaitGroup

	mu      sync.Mutex // one writer at a time: the turn and the heartbeat
	started bool
}

// send writes one frame. A write that fails means the client left: net/http then cancels the
// request's context, and that is what ends the turn.
func (w *chatStream) send(e agent.ChatEvent) {
	data, err := json.Marshal(chatFrameData(e))
	if err != nil {
		// Only the error's type: a frame holds the answer's words.
		w.log.Error("encode chat frame", "event", e.Type, "errorType", fmt.Sprintf("%T", err))
		return
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if !w.started {
		w.started = true
		h := w.res.Header()
		h.Set(echo.HeaderContentType, "text/event-stream")
		h.Set(echo.HeaderCacheControl, "no-store")
		h.Set("X-Accel-Buffering", "no")
		w.res.WriteHeader(http.StatusOK)
		safe.Go(&w.beats, "chat heartbeat", w.heartbeat)
	}
	_, _ = fmt.Fprintf(w.res, "event: %s\ndata: %s\n\n", e.Type, data)
	w.res.Flush()
}

func (w *chatStream) heartbeat() {
	ticker := time.NewTicker(w.every)
	defer ticker.Stop()
	for {
		select {
		case <-w.stop:
			return
		case <-ticker.C:
			w.mu.Lock()
			_, _ = w.res.Write([]byte(": keep-alive\n\n"))
			w.res.Flush()
			w.mu.Unlock()
		}
	}
}

// close ends the heartbeat before the handler returns: nothing may write to the response after.
func (w *chatStream) close() {
	close(w.stop)
	w.beats.Wait()
}

// chatFrameData is an event's `data:` line, in the shapes openapi.yaml documents.
func chatFrameData(e agent.ChatEvent) any {
	switch e.Type {
	case agent.ChatEventComponents:
		return chatComponentsFrame(e)
	case agent.ChatEventDone:
		var turn uuid.UUID
		if e.TurnID != nil {
			turn = *e.TurnID
		}
		return api.ChatDoneFrame{TurnId: apiid.From(turn)}
	case agent.ChatEventError:
		return api.ChatErrorFrame{Code: api.ChatErrorFrameCode(e.Code), Message: e.Text}
	default:
		return api.ChatTextFrame{Text: e.Text}
	}
}

// componentsFrameJSON is api.ChatComponentsFrame with the plan as plans are always written (planJSON).
type componentsFrameJSON struct {
	Titles        []api.TitleSummary `json:"titles,omitempty"`
	Plan          *planJSON          `json:"plan,omitempty"`
	ImportID      *apiid.UUID        `json:"importId,omitempty"`
	ActionID      *apiid.UUID        `json:"actionId,omitempty"`
	ActionSummary string             `json:"actionSummary,omitempty"`
}

func chatComponentsFrame(e agent.ChatEvent) componentsFrameJSON {
	frame := componentsFrameJSON{
		ImportID: apiid.PtrOrNil(e.ImportID), ActionID: apiid.PtrOrNil(e.ActionID), ActionSummary: e.ActionSummary,
	}
	for _, t := range e.Titles {
		frame.Titles = append(frame.Titles, TitleSummaryDTO(t))
	}
	if e.Plan != nil {
		plan := planDTO(*e.Plan)
		frame.Plan = &plan
	}
	return frame
}

// chatTranscribe is `POST /v1/chats/transcribe`: one spoken question as text. The audio stays in this
// function's memory and goes nowhere but the transcription service; neither it nor the words reach a log.
func (s *Server) chatTranscribe(c *echo.Context) error {
	ctx := c.Request().Context()
	user, err := currentUser(ctx)
	if err != nil {
		return err
	}
	if s.Transcription == nil {
		return errVoiceUnavailable
	}
	mediaType := contentType(c)
	if mediaType != "application/octet-stream" && !strings.HasPrefix(mediaType, "audio/") {
		return errUnreadable
	}
	// What the client measured. A header that is no number says nothing; the size limit still holds.
	if seconds, err := strconv.ParseFloat(c.Request().Header.Get("X-Audio-Seconds"), 64); err == nil && seconds > maxChatAudioSeconds {
		return errAudioTooLong
	}
	select {
	case s.transcribing <- struct{}{}:
		defer func() { <-s.transcribing }()
	default:
		return errVoiceBusy // before Allow: a busy server does not spend the user's hour
	}
	if !s.transcriptions.Allow(user.String(), time.Now()) {
		return errTooManyVoice
	}
	audio, err := readUpload(c, maxChatAudioBytes, errAudioTooLarge)
	if err != nil {
		return err
	}
	if len(audio) == 0 {
		return errTranscriptionEmpty
	}
	names, err := s.q.InProgressTitleNames(ctx, sqlc.InProgressTitleNamesParams{UserID: user, Limit: maxVocabularyTitles})
	if err != nil {
		return fmt.Errorf("transcription vocabulary: %w", err)
	}
	result, err := s.Transcription.Transcribe(ctx, audio, c.Request().Header.Get(echo.HeaderContentType), strings.Join(names, ", "))
	switch {
	case errors.Is(err, transcription.ErrEmpty):
		return errTranscriptionEmpty
	case err != nil && ctx.Err() != nil:
		return err // the client left; not a failure of the service
	case err != nil:
		s.Log.WarnContext(ctx, "transcription failed", "error", err.Error())
		return apperr.ProviderUnavailable("transcription", "Voice")
	}
	return c.JSON(http.StatusOK, api.ChatTranscript{Text: result.Text, Language: result.Language})
}

// chatExports is AccountExport.chats: every chat of the user with its turns.
func (s *Server) chatExports(ctx context.Context, user uuid.UUID) ([]api.ChatExport, error) {
	chats, err := s.chats().ForExport(ctx, user)
	if err != nil {
		return nil, err
	}
	out := make([]api.ChatExport, 0, len(chats))
	for _, chat := range chats {
		turns := make([]api.ChatExportTurn, 0, len(chat.Turns))
		for _, t := range chat.Turns {
			turns = append(turns, api.ChatExportTurn{
				Role: api.ChatExportTurnRole(t.Role), Body: t.Body, CreatedAt: apitime.From(t.CreatedAt),
			})
		}
		out = append(out, api.ChatExport{Title: chat.Title, CreatedAt: apitime.From(chat.CreatedAt), Turns: turns})
	}
	return out, nil
}
