package push

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/testdb"
	"context"
	"crypto/rand"
	"encoding/hex"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeSender records what would have gone to Apple or a browser; some tokens are "dead".
type fakeSender struct {
	mu   sync.Mutex
	dead map[string]bool
	apns []struct {
		m Message
		d Device
	}
	web []struct {
		m Message
		s WebSubscription
	}
}

func (f *fakeSender) Send(_ context.Context, m Message, d Device) (Outcome, error) {
	if f.dead[d.Token] {
		return DeadToken, nil
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.apns = append(f.apns, struct {
		m Message
		d Device
	}{m, d})
	return Sent, nil
}

type fakeWeb struct{ fakeSender }

func (f *fakeWeb) PublicKey() string { return "BPublicKeyForTests_abcdefghijklmnop" }

func (f *fakeWeb) Send(_ context.Context, m Message, s WebSubscription) (Outcome, error) {
	if f.dead[s.Endpoint] {
		return DeadToken, nil
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.web = append(f.web, struct {
		m Message
		s WebSubscription
	}{m, s})
	return Sent, nil
}

func deviceToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

type airingEnv struct {
	pool    *pgxpool.Pool
	q       *sqlc.Queries
	user    uuid.UUID
	title   uuid.UUID
	item    uuid.UUID
	optIn   time.Time
	svc     *Service
	ctx     context.Context
	testing *testing.T
}

// newAiringEnv is a user watching a show, with episodes airing at the given offsets from now.
func newAiringEnv(t *testing.T, name string, airs ...time.Duration) *airingEnv {
	t.Helper()
	pool := testdb.New(t)
	ctx := context.Background()
	e := &airingEnv{pool: pool, q: sqlc.New(pool), user: uuid.New(), title: uuid.New(), item: uuid.New(), optIn: time.Now(), ctx: ctx, testing: t}
	e.svc = &Service{Q: e.q}
	exec := func(sql string, args ...any) {
		_, err := pool.Exec(ctx, sql, args...)
		require.NoError(t, err)
	}
	exec(`INSERT INTO users (id) VALUES ($1)`, e.user)
	exec(`INSERT INTO titles (id, type, title) VALUES ($1, 'show', $2)`, e.title, name)
	for i, offset := range airs {
		exec(`INSERT INTO show_episodes (id, title_id, season, episode, name, airs_at) VALUES ($1, $2, 1, $3, $4, $5)`,
			uuid.New(), e.title, i+1, "Episode "+string(rune('1'+i)), e.optIn.Add(offset))
	}
	exec(`INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at) VALUES ($1, $2, $3, 'in_progress', now(), now())`,
		e.item, e.user, e.title)
	return e
}

func (e *airingEnv) watched(episode int) {
	_, err := e.pool.Exec(e.ctx, `INSERT INTO episode_progress (id, library_item_id, season, episode) VALUES ($1, $2, 1, $3)`,
		uuid.New(), e.item, episode)
	require.NoError(e.testing, err)
}

func TestAiringAnnouncedOnce(t *testing.T) {
	hour := time.Hour
	e := newAiringEnv(t, "Severance", -24*hour, hour, hour, 5*hour)
	e.watched(3)
	live, dead := deviceToken(), deviceToken()
	require.NoError(t, e.svc.RegisterDevice(e.ctx, e.user, live, Production, "com.fernandocorreia.aaru.beta"))
	require.NoError(t, e.svc.RegisterDevice(e.ctx, e.user, dead, Sandbox, "com.fernandocorreia.aaru.beta"))
	require.NoError(t, e.svc.SaveNotificationSettings(e.ctx, e.user, Settings{Airing: true}, e.optIn))

	sender := &fakeSender{dead: map[string]bool{dead: true}}
	n := &AiringNotifier{Q: e.q, APNs: sender, Now: func() time.Time { return e.optIn.Add(2 * hour) }}
	_, err := n.RunOnce(e.ctx)
	require.NoError(t, err)
	_, err = n.RunOnce(e.ctx)
	require.NoError(t, err)

	require.Len(t, sender.apns, 1, "episode 2 only, and only once")
	got := sender.apns[0]
	assert.Equal(t, "Severance", got.m.Title)
	assert.Equal(t, "S1 E2 · “Episode 2” is out", got.m.Body)
	assert.Equal(t, strings.ToUpper(e.item.String()), got.m.Payload["libraryItemId"], "a tap opens the library item")
	assert.Equal(t, strings.ToUpper(e.title.String()), got.m.Payload["titleId"])
	assert.Equal(t, live, got.d.Token)
	devices, err := e.svc.Devices(e.ctx, e.user)
	require.NoError(t, err)
	assert.Equal(t, []Device{{Token: live, Environment: Production, Topic: "com.fernandocorreia.aaru.beta"}}, devices, "dead token forgotten")
}

func TestAiringNotSentWithoutOptIn(t *testing.T) {
	e := newAiringEnv(t, "Quiet Show", -time.Minute)
	require.NoError(t, e.svc.RegisterDevice(e.ctx, e.user, deviceToken(), Production, "com.fernandocorreia.aaru"))
	sender := &fakeSender{}
	sent, err := (&AiringNotifier{Q: e.q, APNs: sender}).RunOnce(e.ctx)
	require.NoError(t, err)
	assert.Zero(t, sent)
	assert.Empty(t, sender.apns)
}

func TestAiringReachesABrowserOnlyUser(t *testing.T) {
	e := newAiringEnv(t, "Pluribus", time.Minute)
	require.NoError(t, e.svc.SaveNotificationSettings(e.ctx, e.user, Settings{Airing: true}, e.optIn))
	live, dead := "https://fcm.googleapis.com/fcm/send/"+uuid.NewString(), "https://fcm.googleapis.com/fcm/send/"+uuid.NewString()
	for _, endpoint := range []string{live, dead} {
		require.NoError(t, e.q.SaveWebPushSubscription(e.ctx, sqlc.SaveWebPushSubscriptionParams{
			Endpoint: endpoint, UserID: e.user, P256dh: "p", Auth: "a", VapidKeyID: "k",
		}))
	}
	web := &fakeWeb{fakeSender{dead: map[string]bool{dead: true}}}
	n := &AiringNotifier{Q: e.q, Web: web, Now: func() time.Time { return e.optIn.Add(time.Hour) }}
	sent, err := n.RunOnce(e.ctx)
	require.NoError(t, err)
	assert.Equal(t, 1, sent)
	require.Len(t, web.web, 1)
	assert.Equal(t, live, web.web[0].s.Endpoint)
	assert.Equal(t, strings.ToUpper(e.item.String()), web.web[0].m.Payload["libraryItemId"])
	subs, err := e.svc.WebSubscriptions(e.ctx, e.user)
	require.NoError(t, err)
	require.Len(t, subs, 1)
	assert.Equal(t, live, subs[0].Endpoint)
}
