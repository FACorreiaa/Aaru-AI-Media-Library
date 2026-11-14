package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/groups"
	"aaru-go-api/internal/model"
	"context"
	"fmt"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// `@aaru` answers in #ai-reply (owner 2026-11-14): one channel per group, made on the first
// mention, so a 15-person group is not answered in every channel.

func (e *groupEnv) agentReplyChannels(group string) []map[string]any {
	e.t.Helper()
	var out []map[string]any
	for _, c := range maps(e.get("/v1/groups/" + group)["channels"]) {
		if c["agentReplies"] == true {
			out = append(out, c)
		}
	}
	return out
}

// The caps are a product decision; changing them is a decision too, not a refactor.
func TestAgentCapsArePinned(t *testing.T) {
	assert.Equal(t, 30, groups.AgentDailyCapPerUser)
	assert.Equal(t, 10, groups.AgentHourlyCapPerGroup)
	assert.Contains(t, groups.RestingNote, "30 questions a day")
	assert.Contains(t, groups.RestingNote, "10 an hour")
}

func TestFirstMentionMakesAIReplyOnceAndTheAnswerLandsThere(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("First answer."), textResponse("Second answer.")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	rec := env.send(http.MethodPost, "/v1/groups/"+group+"/channels", map[string]any{"kind": "text", "name": "movie-night"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	night := decode[map[string]any](t, rec)["id"].(string)
	assert.Empty(t, env.agentReplyChannels(group), "no #ai-reply before anyone asks")

	first := env.post(channelPath(group, general), "@aaru what's on?")
	second := env.post(channelPath(group, night), "@aaru and here?")
	made := env.agentReplyChannels(group)
	require.Len(t, made, 1, "made once")
	aiReply := made[0]
	assert.Equal(t, groups.AgentRepliesName, aiReply["name"])
	assert.Equal(t, "text", aiReply["kind"])
	assert.Equal(t, false, aiReply["isDefault"])
	for _, c := range maps(env.get("/v1/groups/" + group)["channels"]) {
		if c["id"] != aiReply["id"] {
			assert.Less(t, c["position"].(float64), aiReply["position"].(float64), "last in the group")
		}
	}

	replies := env.replies(m, nil)
	for range 2 {
		worked, err := replies.RunNext(context.Background())
		require.NoError(t, err)
		require.True(t, worked)
	}
	path := channelPath(group, aiReply["id"].(string))
	answers := agentMessages(items(t, env.send(http.MethodGet, path+"/messages", nil)))
	require.Len(t, answers, 2)
	assert.Equal(t, first["id"], answers[0]["replyTo"])
	assert.Equal(t, general, answers[0]["replyToChannelId"])
	assert.Equal(t, second["id"], answers[1]["replyTo"])
	assert.Equal(t, night, answers[1]["replyToChannelId"])
	for _, c := range []string{general, night} {
		list := items(t, env.send(http.MethodGet, channelPath(group, c)+"/messages", nil))
		assert.Empty(t, agentMessages(list), "nothing answered in place")
		require.Len(t, list, 1)
		assert.Equal(t, aiReply["id"], list[0]["answeredIn"], "the mention says where Aaru answered")
	}
	var count int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM group_channels WHERE is_agent_replies`).Scan(&count))
	assert.Equal(t, 1, count)
}

func TestAIReplyIsMadeOnceUnderConcurrentAnswers(t *testing.T) {
	env := newAgentEnv(t, &scriptedModel{})
	env.claimHandle()
	group, general := env.createGroup("Film club")
	mention := env.post(channelPath(group, general), "hello there")
	g, source, replyTo := uuid.MustParse(group), uuid.MustParse(general), uuid.MustParse(mention["id"].(string))
	var wg sync.WaitGroup
	errs := make([]error, 8)
	for i := range errs {
		wg.Go(func() {
			_, errs[i] = env.server.Groups.PostAgentReply(context.Background(), g, source, replyTo, "hi", nil, nil)
		})
	}
	wg.Wait()
	for _, err := range errs {
		require.NoError(t, err)
	}
	require.Len(t, env.agentReplyChannels(group), 1)
	assert.Len(t, agentMessages(items(t, env.send(http.MethodGet, env.aiReplyPath(group)+"/messages", nil))), len(errs))
}

func TestTheModelReadsTheChannelItWasAskedIn(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("One."), textResponse("Two.")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	env.post(channelPath(group, general), "we keep talking about Heat")
	env.post(channelPath(group, general), "@aaru is it long?")
	replies := env.replies(m, nil)
	_, err := replies.RunNext(context.Background())
	require.NoError(t, err)
	// A member writes in #ai-reply; a second mention in #general still reads #general only.
	env.post(env.aiReplyPath(group), "a side note only in ai-reply")
	env.post(channelPath(group, general), "@aaru and the sequel?")
	_, err = replies.RunNext(context.Background())
	require.NoError(t, err)
	calls := m.calls()
	require.Len(t, calls, 2)
	prompt := string(calls[1].Turns[0].Content[0])
	assert.Contains(t, prompt, "#general")
	assert.Contains(t, prompt, "we keep talking about Heat")
	assert.Contains(t, prompt, "and the sequel?")
	assert.NotContains(t, prompt, "a side note only in ai-reply")
}

func TestAgentThinkingShowsInBothChannels(t *testing.T) {
	env := newAgentEnv(t, &scriptedModel{})
	env.claimHandle()
	group, general := env.createGroup("Film club")
	socket := env.listen(env.user)
	mention := env.post(channelPath(group, general), "@aaru hi")
	aiReply := env.agentReplyChannels(group)[0]["id"]
	var thinkingIn []any
	for _, f := range socket.all() {
		if f["type"] == "agent.thinking" {
			assert.Equal(t, mention["id"], f["messageId"])
			thinkingIn = append(thinkingIn, f["channelId"])
		}
	}
	assert.ElementsMatch(t, []any{general, aiReply}, thinkingIn)
}

func TestTheRestingNoteGoesToAIReplyAndTheCapsHold(t *testing.T) {
	m := &scriptedModel{}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	channel := channelPath(group, general)
	for number := 1; number <= groups.AgentHourlyCapPerGroup+3; number++ {
		env.post(channel, fmt.Sprintf("@aaru question %d", number))
	}
	assert.Empty(t, agentMessages(items(t, env.send(http.MethodGet, channel+"/messages", nil))))
	notes := agentMessages(items(t, env.send(http.MethodGet, env.aiReplyPath(group)+"/messages", nil)))
	require.Len(t, notes, 1, "resting once, then quiet")
	assert.Equal(t, groups.RestingNote, notes[0]["body"])
	assert.Equal(t, general, notes[0]["replyToChannelId"])
	var queued int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM agent_replies WHERE state = 'queued'`).Scan(&queued))
	assert.Equal(t, groups.AgentHourlyCapPerGroup, queued)
	assert.Empty(t, m.calls())
}

func TestAIReplyNameIsReservedButARenameKeepsTheChannel(t *testing.T) {
	m := &scriptedModel{script: []model.Response{textResponse("One."), textResponse("Two.")}}
	env := newAgentEnv(t, m)
	env.claimHandle()
	group, general := env.createGroup("Film club")
	for _, name := range []string{"ai-reply", "AI Reply"} {
		rec := env.send(http.MethodPost, "/v1/groups/"+group+"/channels", map[string]any{"kind": "text", "name": name})
		assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, name)
	}
	env.post(channelPath(group, general), "@aaru one")
	replies := env.replies(m, nil)
	_, err := replies.RunNext(context.Background())
	require.NoError(t, err)
	made := env.agentReplyChannels(group)[0]
	rec := env.send(http.MethodPatch, channelPath(group, made["id"].(string)), map[string]any{"name": "owl"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	// A member cannot rename another channel to the reserved name either.
	rec = env.send(http.MethodPatch, channelPath(group, general), map[string]any{"name": "ai-reply"})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)

	env.post(channelPath(group, general), "@aaru two")
	_, err = replies.RunNext(context.Background())
	require.NoError(t, err)
	after := env.agentReplyChannels(group)
	require.Len(t, after, 1, "found by its flag, not its name")
	assert.Equal(t, made["id"], after[0]["id"])
	assert.Equal(t, "owl", after[0]["name"])
	assert.Len(t, agentMessages(items(t, env.send(http.MethodGet, env.aiReplyPath(group)+"/messages", nil))), 2)
}

func TestAnOldChannelNamedAIReplyIsNotTakenOver(t *testing.T) {
	env := newAgentEnv(t, &scriptedModel{})
	env.claimHandle()
	group, general := env.createGroup("Film club")
	// Made before the name was reserved.
	env.exec(`INSERT INTO group_channels (id, group_id, kind, name, position, created_at) VALUES ($1, $2, 'text', 'ai-reply', 5, now())`,
		uuid.New(), uuid.MustParse(group))
	env.post(channelPath(group, general), "@aaru hi")
	made := env.agentReplyChannels(group)
	require.Len(t, made, 1)
	assert.Equal(t, "ai-reply-2", made[0]["name"])
}

func TestAnAnswerFromATitleChannelKeepsItsSpoilerStampInAIReply(t *testing.T) {
	env := newAgentEnv(t, &scriptedModel{})
	tmdb := env.stubShow("Severance", catalog.StatusReturning, 2, 5, false)
	fx := env.setUpKind("title", map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}})
	env.watch(tmdb, [][2]int{{1, 1}, {1, 2}, {1, 3}})
	anaItem := env.watch(tmdb, [][2]int{{1, 1}}, fx.ana.Token)
	mention := env.post(channelPath(fx.group, fx.channel), "what happens next?")
	socket := env.listen(fx.ana.uid)
	_, err := env.server.Groups.PostAgentReply(context.Background(), uuid.MustParse(fx.group), uuid.MustParse(fx.channel),
		uuid.MustParse(mention["id"].(string)), "In episode 3 …", nil, groups.EpisodeStamp(groups.EpisodePoint{Season: 1, Episode: 3}))
	require.NoError(t, err)

	path := env.aiReplyPath(fx.group)
	veiled := func(token ...string) any {
		list := agentMessages(items(t, env.send(http.MethodGet, path+"/messages", nil, token...)))
		require.Len(t, list, 1)
		return list[0]["veiled"]
	}
	assert.Equal(t, true, veiled(fx.ana.Token), "Ana is at S1E1")
	assert.Equal(t, false, veiled(), "the owner is at S1E3")
	created := false
	for _, f := range socket.all() {
		if f["type"] == "message.created" {
			created = true
			assert.Equal(t, true, f["message"].(map[string]any)["veiled"], "veiled live too")
		}
	}
	assert.True(t, created)
	for _, ep := range [][2]int{{1, 2}, {1, 3}} {
		env.tick(anaItem, ep, fx.ana.Token)
	}
	assert.Equal(t, false, veiled(fx.ana.Token), "caught up")
}

func TestAStampAboutNoKnownTitleIsHiddenInATextChannel(t *testing.T) {
	env := newAgentEnv(t, &scriptedModel{})
	env.claimHandle()
	ana := env.friend(env.user)
	group, general := env.createGroup("Film club")
	env.join(ana, group)
	mention := env.post(channelPath(group, general), "hello")
	// A plain text channel's mention gives no title; a stamp anyway is hidden from every reader.
	_, err := env.server.Groups.PostAgentReply(context.Background(), uuid.MustParse(group), uuid.MustParse(general),
		uuid.MustParse(mention["id"].(string)), "the ending is …", nil, groups.EndingStamp())
	require.NoError(t, err)
	for _, token := range [][]string{nil, {ana.Token}} {
		list := agentMessages(items(t, env.send(http.MethodGet, env.aiReplyPath(group)+"/messages", nil, token...)))
		require.Len(t, list, 1)
		assert.Equal(t, true, list[0]["veiled"])
	}
}
