package httpapi

import (
	"aaru-go-api/internal/model"
	"bytes"
	"context"
	"image"
	"image/png"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AI sharing (PRV-002): the answer on `Me`, the endpoint that sets it, and the gate on every path
// that sends a user's data to the model. The harness signs users in as allowed; these tests take
// that away.

// setAISharing puts a user in a state: nil is unanswered.
func (h *harness) setAISharing(user uuid.UUID, allowed *bool) {
	h.t.Helper()
	_, err := h.pool.Exec(context.Background(),
		`UPDATE users SET ai_sharing_allowed = $2, ai_sharing_decided_at = CASE WHEN $2::boolean IS NULL THEN NULL ELSE now() END WHERE id = $1`,
		user, allowed)
	require.NoError(h.t, err)
}

// notAllowed is the two states that send nothing.
var notAllowed = map[string]*bool{"unanswered": nil, "declined": new(false)}

func requireAISharing(t *testing.T, code int, body map[string]any) {
	t.Helper()
	assert.Equal(t, http.StatusForbidden, code)
	assert.Equal(t, "ai_sharing_required", body["code"])
}

func TestAISharingStartsUnansweredAndTheLatestAnswerHolds(t *testing.T) {
	env := newLibEnv(t)
	env.setAISharing(env.user, nil)
	sharing := func() map[string]any { return env.json(http.MethodGet, "/v1/me", nil)["aiSharing"].(map[string]any) }
	assert.Equal(t, "unanswered", sharing()["state"])
	assert.Nil(t, sharing()["decidedAt"])

	rec := env.send(http.MethodPut, "/v1/me/ai-sharing", map[string]any{"allowed": true})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	answered := decode[map[string]any](t, rec)
	assert.Equal(t, "allowed", answered["state"])
	assert.NotEmpty(t, answered["decidedAt"])
	assert.Equal(t, "allowed", sharing()["state"])
	assert.Equal(t, answered["decidedAt"], sharing()["decidedAt"])

	rec = env.send(http.MethodPut, "/v1/me/ai-sharing", map[string]any{"allowed": false})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Equal(t, "declined", sharing()["state"])
	assert.NotEmpty(t, sharing()["decidedAt"])

	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodPut, "/v1/me/ai-sharing", map[string]any{}).Code)
	assert.Equal(t, http.StatusUnauthorized, env.send(http.MethodPut, "/v1/me/ai-sharing", map[string]any{"allowed": true}, "nope").Code)
}

func TestAISharingIsOneUsersOwn(t *testing.T) {
	env := newLibEnv(t)
	other, _ := env.signIn()
	env.setAISharing(other, nil)
	rec := env.send(http.MethodPut, "/v1/me/ai-sharing", map[string]any{"allowed": false})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	var allowed *bool
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT ai_sharing_allowed FROM users WHERE id = $1`, other).Scan(&allowed))
	assert.Nil(t, allowed, "another account stays as it was")
}

func TestAISharingIsInTheExport(t *testing.T) {
	env := newLibEnv(t)
	rec := env.send(http.MethodGet, "/v1/me/export?format=json", nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	account := decode[map[string]any](t, rec)["account"].(map[string]any)
	assert.Equal(t, "allowed", account["aiSharing"].(map[string]any)["state"])
}

func TestChatTurnNeedsAISharingAndCallsNoModel(t *testing.T) {
	for name, state := range notAllowed {
		t.Run(name, func(t *testing.T) {
			m := &chatModel{}
			e := newChatEnv(t, m)
			chat := e.newChat(e.bearer)
			e.setAISharing(e.user, state)
			rec := e.send(http.MethodPost, "/v1/chats/"+chat+"/turns", map[string]any{"body": "what should I watch?"})
			requireAISharing(t, rec.Code, decode[map[string]any](t, rec))
			gates, mains := m.counts()
			assert.Zero(t, gates+mains, "no model call")
			assert.Zero(t, e.count(`SELECT count(*)::int FROM chat_turns WHERE chat_id = $1::uuid`, chat), "nothing stored")
			// Reading and deleting what is already there still works.
			assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/chats", nil).Code)
			assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/chats/"+chat, nil).Code)
		})
	}
}

func TestChatFileNeedsAISharingAndKeepsNothing(t *testing.T) {
	for name, state := range notAllowed {
		t.Run(name, func(t *testing.T) {
			e := newChatEnv(t, &chatModel{})
			chat := e.newChat(e.bearer)
			e.setAISharing(e.user, state)
			code, body := e.attach(chat, "notes.txt", "text/plain", []byte("Heat (1995)"))
			requireAISharing(t, code, body)
			assert.Zero(t, e.count(`SELECT count(*)::int FROM chat_attachments WHERE chat_id = $1::uuid`, chat))
		})
	}
}

func TestTranscribeNeedsAISharingAndNeverReachesWhisper(t *testing.T) {
	for name, state := range notAllowed {
		t.Run(name, func(t *testing.T) {
			stub := newWhisperStub(t, "hello")
			e := newChatEnv(t, nil, stub.on(t))
			e.setAISharing(e.user, state)
			rec := e.transcribe(e.bearer, "audio/mp4", []byte("fake-audio-bytes"), "3")
			requireAISharing(t, rec.Code, decode[map[string]any](t, rec))
			assert.Empty(t, stub.seen())
		})
	}
}

func TestCaptureNeedsAISharingForTextAndPicturesButNotLinks(t *testing.T) {
	var buf bytes.Buffer
	require.NoError(t, png.Encode(&buf, image.NewGray(image.Rect(0, 0, 2, 2))))
	for name, state := range notAllowed {
		t.Run(name, func(t *testing.T) {
			m := &captureModel{responses: []model.Response{captureReport([2]any{"Heat", 1995})}}
			env := newCaptureEnv(t, m, nil)
			env.setAISharing(env.user, state)

			rec := env.send(http.MethodPost, "/v1/imports/capture", map[string]any{"text": "Heat (1995)"})
			requireAISharing(t, rec.Code, decode[map[string]any](t, rec))
			rec = env.upload("/v1/imports/capture", "image/png", buf.Bytes())
			requireAISharing(t, rec.Code, decode[map[string]any](t, rec))
			env.runImports()
			assert.Empty(t, m.requests, "no model call")
			var kept, jobs int
			ctx := context.Background()
			require.NoError(t, env.pool.QueryRow(ctx, `SELECT count(*)::int FROM capture_inputs WHERE user_id = $1`, env.user).Scan(&kept))
			require.NoError(t, env.pool.QueryRow(ctx, `SELECT count(*)::int FROM import_jobs WHERE user_id = $1`, env.user).Scan(&jobs))
			assert.Zero(t, kept, "nothing kept")
			assert.Zero(t, jobs, "no job made")

			// A link is read by its id on Aaru's server and sends nothing to the model.
			tmdb := env.captureFilm("Linked " + uuid.NewString())
			rec = env.send(http.MethodPost, "/v1/imports/capture", map[string]any{"url": "https://www.themoviedb.org/movie/" + tmdb + "-linked"})
			assert.Equal(t, http.StatusAccepted, rec.Code, rec.Body.String())
		})
	}
}

func TestCaptureSentThenAISharingTurnedOffIsNeverRead(t *testing.T) {
	m := &captureModel{responses: []model.Response{captureReport([2]any{"Heat", 1995})}}
	env := newCaptureEnv(t, m, nil)
	rec := env.send(http.MethodPost, "/v1/imports/capture", map[string]any{"text": "Heat (1995)"})
	require.Equal(t, http.StatusAccepted, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.setAISharing(env.user, new(false))
	env.runImports()
	assert.Empty(t, m.requests, "no model call")
	job, _ := env.importDetail(id)
	assert.Equal(t, "failed", job["state"])
	assert.Contains(t, job["errorSummary"], "AI data sharing is off")
	assert.Nil(t, env.captureInput(id), "the text is deleted")
}

func TestTaggingAaruNeedsAISharingAndPostsNothing(t *testing.T) {
	for name, state := range notAllowed {
		t.Run(name, func(t *testing.T) {
			m := &scriptedModel{script: []model.Response{textResponse("never said")}}
			env := newAgentEnv(t, m)
			env.claimHandle()
			ana := env.friend(env.user)
			group, general := env.createGroup("Film club")
			env.join(ana, group)
			env.setAISharing(ana.uid, state)
			channel := channelPath(group, general)

			rec := env.send(http.MethodPost, channel+"/messages", map[string]any{"body": "@aaru what next?"}, ana.Token)
			requireAISharing(t, rec.Code, decode[map[string]any](t, rec))
			assert.Empty(t, items(t, env.send(http.MethodGet, channel+"/messages", nil)), "the group sees nothing")
			worked, err := env.replies(m, nil).RunNext(context.Background())
			require.NoError(t, err)
			assert.False(t, worked, "nothing queued")
			assert.Empty(t, m.calls())

			// Everything else in the group works as before.
			posted := env.post(channel, "no tag here", ana.Token)
			assert.Equal(t, false, posted["mentionsAgent"])
		})
	}
}

func TestAaruIsSentOnlyTheMessagesOfMembersWhoAllowed(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("Here you go.")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	ana, ben, cleo := env.friend(env.user), env.friend(env.user), env.friend(env.user)
	group, general := env.createGroup("Film club")
	for _, p := range []groupMember{ana, ben, cleo} {
		env.join(p, group)
	}
	env.setAISharing(ben.uid, nil)
	env.setAISharing(cleo.uid, new(false))
	channel := channelPath(group, general)
	env.post(channel, "the owner said this")
	env.post(channel, "ana said this", ana.Token)
	env.post(channel, "ben kept this to the group", ben.Token)
	env.post(channel, "cleo kept this to the group", cleo.Token)
	mention := env.post(channel, "@aaru sum it up", ana.Token)

	worked, err := env.replies(m, nil).RunNext(context.Background())
	require.NoError(t, err)
	require.True(t, worked)
	require.Len(t, m.calls(), 1)
	seen := m.everythingSeen()
	assert.Contains(t, seen, "the owner said this")
	assert.Contains(t, seen, "ana said this")
	assert.Contains(t, seen, "@aaru sum it up")
	assert.NotContains(t, seen, "ben kept this")
	assert.NotContains(t, seen, "cleo kept this")
	assert.NotContains(t, seen, ben.Handle)
	assert.NotContains(t, seen, cleo.Handle)

	// The reply is posted like any other, and the channel still shows everyone's messages.
	list := items(t, env.send(http.MethodGet, channel+"/messages", nil))
	require.Len(t, list, 6)
	assert.Equal(t, mention["id"], list[len(list)-1]["replyTo"])
}

func TestTaggerWhoTurnsAISharingOffBeforeTheAnswerGetsNone(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("never said")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	env.post(channel, "@aaru what next?")
	env.setAISharing(env.user, new(false))

	replies := env.replies(m, nil)
	worked, err := replies.RunNext(context.Background())
	require.NoError(t, err)
	assert.True(t, worked, "the job is taken and closed")
	assert.Empty(t, m.calls())
	assert.Empty(t, agentMessages(items(t, env.send(http.MethodGet, channel+"/messages", nil))))
	worked, err = replies.RunNext(context.Background())
	require.NoError(t, err)
	assert.False(t, worked, "and not tried again")
}
