package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/token"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Sign-in flows end to end over HTTP, against Postgres, with stubbed Apple, Google and email.

type fixedApple struct{ subject string }

func (f fixedApple) Verify(_ context.Context, identityToken, _ string) (auth.AppleIdentity, error) {
	if identityToken != "good" {
		return auth.AppleIdentity{}, auth.ErrInvalidToken
	}
	email := "x@privaterelay.appleid.com"
	return auth.AppleIdentity{Subject: f.subject, Email: &email, IsPrivateRelay: true}, nil
}

type fixedGoogle struct{ subject string }

func (f fixedGoogle) Verify(_ context.Context, idToken string, _ *string) (auth.GoogleIdentity, error) {
	if idToken != "good" {
		return auth.GoogleIdentity{}, auth.ErrInvalidToken
	}
	email, name := "g@example.com", "Gee"
	return auth.GoogleIdentity{Subject: f.subject, Email: &email, Name: &name}, nil
}

// outbox captures the links and codes the server "emails".
type outbox struct {
	mu   sync.Mutex
	sent []struct{ link, code string }
}

func (o *outbox) Send(_ context.Context, _, link, code string) error {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.sent = append(o.sent, struct{ link, code string }{link, code})
	return nil
}

func (o *outbox) last(t *testing.T) (token, code string) {
	t.Helper()
	o.mu.Lock()
	defer o.mu.Unlock()
	require.NotEmpty(t, o.sent)
	last := o.sent[len(o.sent)-1]
	u, err := url.Parse(last.link)
	require.NoError(t, err)
	return u.Query().Get("token"), last.code
}

// authHarness has a fixed Apple subject, an outbox for email, and optionally Google.
func authHarness(t *testing.T, mail *outbox, google auth.GoogleVerifying, tweak ...func(*Deps)) *harness {
	t.Helper()
	return newHarness(t, append([]func(*Deps){func(d *Deps) {
		d.Auth.Apple = fixedApple{subject: uuid.NewString()}
		d.Auth.Google = google
		if mail != nil {
			base, _ := url.Parse("https://aaru.test/auth/verify")
			d.Auth.MagicLinks = &auth.MagicLinks{Sender: mail, LinkBaseURL: base}
		}
	}}, tweak...)...)
}

// send is a request with any headers and a raw body.
func (h *harness) send(method, path string, headers map[string]string, body string) *httptest.ResponseRecorder {
	h.t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, reader)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.echo.ServeHTTP(rec, req)
	return rec
}

func (h *harness) signInApple(name *string) api.Session {
	h.t.Helper()
	body := map[string]any{"identityToken": "good", "nonce": "n"}
	if name != nil {
		body["displayName"] = *name
	}
	rec := h.do(http.MethodPost, "/v1/auth/apple", "", body)
	require.Equal(h.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[api.Session](h.t, rec)
}

func TestAppleSignInTwiceIsOneUserAndKeepsTheFirstName(t *testing.T) {
	h := authHarness(t, nil, nil)
	name := "Ana Maria Silva"
	first := h.signInApple(&name)
	second := h.signInApple(nil)
	assert.Equal(t, first.UserId, second.UserId)
	assert.NotEqual(t, first.Token, second.Token)
	assert.WithinDuration(t, time.Now().Add(auth.SessionLifetime), second.ExpiresAt.Time, time.Minute)

	rec := h.do(http.MethodGet, "/v1/me", second.Token, nil)
	require.Equal(t, http.StatusOK, rec.Code)
	me := decode[api.Me](t, rec)
	assert.Equal(t, "Ana", *me.FirstName)
	assert.Equal(t, "Maria Silva", *me.LastName)
	assert.Equal(t, "Ana Maria Silva", *me.DisplayName)
	assert.Equal(t, []api.MeProviders{"apple"}, me.Providers)
	assert.Equal(t, "x@privaterelay.appleid.com", *me.Email)
	assert.False(t, *me.EmailShareable, "a private relay is not shareable")
	assert.Nil(t, me.AvatarUrl)
}

func TestAppleTokenThatDoesNotVerifyIs401(t *testing.T) {
	h := authHarness(t, nil, nil)
	rec := h.do(http.MethodPost, "/v1/auth/apple", "", map[string]string{"identityToken": "forged", "nonce": "n"})
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
	assert.Equal(t, "The Apple sign-in could not be verified.", decode[api.ErrorResponse](t, rec).Message)
}

func TestMagicLinkSignsInOnceThenIsDead(t *testing.T) {
	mail := &outbox{}
	h := authHarness(t, mail, nil)
	email := uuid.NewString() + "@Example.com"
	require.Equal(t, http.StatusAccepted, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": email}).Code)
	link, _ := mail.last(t)
	rec := h.do(http.MethodPost, "/v1/auth/email/verify", "", map[string]string{"token": link})
	require.Equal(t, http.StatusOK, rec.Code)
	me := decode[api.Me](t, h.do(http.MethodGet, "/v1/me", decode[api.Session](t, rec).Token, nil))
	assert.Equal(t, strings.ToLower(email), *me.Email)
	assert.True(t, *me.EmailShareable)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodPost, "/v1/auth/email/verify", "", map[string]string{"token": link}).Code)
}

func TestMagicLinkAppendsToTheBaseQuery(t *testing.T) {
	mail := &outbox{}
	h := authHarness(t, mail, nil, func(d *Deps) {
		d.Auth.MagicLinks.LinkBaseURL, _ = url.Parse("https://aaru.test/auth/verify?from=app")
	})
	require.Equal(t, http.StatusAccepted, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": "q@example.com"}).Code)
	mail.mu.Lock()
	link := mail.sent[0].link
	mail.mu.Unlock()
	assert.True(t, strings.HasPrefix(link, "https://aaru.test/auth/verify?from=app&token="), link)
}

func TestExpiredLinkIsRefusedAndTheTokenIsNeverStoredInClear(t *testing.T) {
	h := authHarness(t, nil, nil)
	ctx := context.Background()
	secret := token.Generate()
	require.NoError(t, h.server.Auth.Store.CreateMagicLink(ctx, "e@x.test", token.Hash(secret), token.EmailCodeHash("000000", "e@x.test"), time.Now().Add(-time.Second)))
	_, ok, err := h.server.Auth.Store.ConsumeMagicLink(ctx, token.Hash(secret), time.Now())
	require.NoError(t, err)
	assert.False(t, ok)
	_, ok, err = h.server.Auth.Store.ConsumeMagicLink(ctx, secret, time.Now())
	require.NoError(t, err)
	assert.False(t, ok)
}

func TestSignInEmailsAreRateLimitedPerAddress(t *testing.T) {
	h := authHarness(t, &outbox{}, nil)
	email := uuid.NewString() + "@example.com"
	var statuses []int
	for range 6 {
		statuses = append(statuses, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": email}).Code)
	}
	assert.Equal(t, []int{202, 202, 202, 202, 202, 429}, statuses)
}

func TestInvalidEmailIs422NamingTheField(t *testing.T) {
	h := authHarness(t, &outbox{}, nil)
	for _, bad := range []string{"not-an-email", "a@b", "@b.c", "a b@c.d", "a@b@c.d"} {
		rec := h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": bad})
		require.Equal(t, http.StatusUnprocessableEntity, rec.Code, bad)
		body := decode[api.ErrorResponse](t, rec)
		assert.Equal(t, "validation_failed", body.Code)
		assert.Equal(t, "Not a valid email address.", (*body.Details)["email"])
	}
}

func TestEmailSignInWithoutResendIs503(t *testing.T) {
	h := authHarness(t, nil, nil)
	rec := h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": "a@b.test"})
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "email_unavailable", decode[api.ErrorResponse](t, rec).Code)
}

func TestSigningOutKillsThatSessionOnly(t *testing.T) {
	h := authHarness(t, nil, nil)
	keep := h.signInApple(nil)
	drop := h.signInApple(nil)
	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/auth/session", drop.Token, nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me", drop.Token, nil).Code)
	assert.Equal(t, http.StatusOK, h.do(http.MethodGet, "/v1/me", keep.Token, nil).Code)
}

func TestAccountDeleteLeavesNoRowReferencingTheUser(t *testing.T) {
	mail := &outbox{}
	h := authHarness(t, mail, nil)
	ctx := context.Background()
	session := h.signInApple(nil)
	userID := session.UserId.ID()
	// Rows in user-owned tables, plus an email identity whose magic link must go too.
	_, err := h.pool.Exec(ctx, `INSERT INTO auth_identities (id, user_id, provider, provider_subject, email) VALUES ($1, $2, 'email', 'del@example.com', 'del@example.com')`, uuid.New(), userID)
	require.NoError(t, err)
	require.Equal(t, http.StatusAccepted, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": "del@example.com"}).Code)
	require.Equal(t, http.StatusCreated, h.do(http.MethodPost, "/v1/agent/tokens", session.Token, map[string]string{"kind": "stremio"}).Code)

	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/me", session.Token, nil).Code)
	assert.Empty(t, rowsReferencing(t, h, userID))
	var links int
	require.NoError(t, h.pool.QueryRow(ctx, `SELECT count(*) FROM magic_links WHERE email = 'del@example.com'`).Scan(&links))
	assert.Zero(t, links)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me", session.Token, nil).Code)
}

// rowsReferencing counts, per table, rows whose user-referencing columns name the user.
func rowsReferencing(t *testing.T, h *harness, userID uuid.UUID) map[string]int {
	t.Helper()
	ctx := context.Background()
	rows, err := h.pool.Query(ctx, `
		SELECT c.table_name, c.column_name FROM information_schema.columns c
		JOIN information_schema.tables t ON t.table_name = c.table_name AND t.table_schema = c.table_schema
		WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND c.data_type = 'uuid'
		  AND (c.column_name = 'user_id' OR c.column_name LIKE '%\_user\_id' OR c.column_name IN ('author_id', 'sender_id', 'recipient_id', 'owner_id'))`)
	require.NoError(t, err)
	type col struct{ table, column string }
	var cols []col
	for rows.Next() {
		var c col
		require.NoError(t, rows.Scan(&c.table, &c.column))
		cols = append(cols, c)
	}
	require.NoError(t, rows.Err())
	out := map[string]int{}
	for _, c := range cols {
		var n int
		require.NoError(t, h.pool.QueryRow(ctx, `SELECT count(*) FROM "`+c.table+`" WHERE "`+c.column+`" = $1`, userID).Scan(&n))
		if n > 0 {
			out[c.table+"."+c.column] = n
		}
	}
	var users int
	require.NoError(t, h.pool.QueryRow(ctx, `SELECT count(*) FROM users WHERE id = $1`, userID).Scan(&users))
	if users > 0 {
		out["users.id"] = users
	}
	return out
}

// APP-002: the 6-digit code that rides in every sign-in email.

func (h *harness) verifyCode(body map[string]string) int {
	h.t.Helper()
	return h.do(http.MethodPost, "/v1/auth/email/verify", "", body).Code
}

func TestEmailedCodeSignsInOnceAndKillsTheLinkToo(t *testing.T) {
	mail := &outbox{}
	h := authHarness(t, mail, nil)
	email := uuid.NewString() + "@example.com"
	require.Equal(t, http.StatusAccepted, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": email}).Code)
	link, code := mail.last(t)
	spaced := code[:3] + " " + code[3:]
	assert.Equal(t, http.StatusOK, h.verifyCode(map[string]string{"email": strings.ToUpper(email), "code": spaced}))
	assert.Equal(t, http.StatusUnauthorized, h.verifyCode(map[string]string{"email": email, "code": code}))
	assert.Equal(t, http.StatusUnauthorized, h.verifyCode(map[string]string{"token": link}))
}

func TestFiveWrongCodesLockTheLinkEvenForTheRightCode(t *testing.T) {
	mail := &outbox{}
	h := authHarness(t, mail, nil)
	email := uuid.NewString() + "@example.com"
	require.Equal(t, http.StatusAccepted, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": email}).Code)
	_, code := mail.last(t)
	wrong := "000000"
	if code == wrong {
		wrong = "000001"
	}
	for range auth.MaxCodeAttempts {
		assert.Equal(t, http.StatusUnauthorized, h.verifyCode(map[string]string{"email": email, "code": wrong}))
	}
	assert.Equal(t, http.StatusUnauthorized, h.verifyCode(map[string]string{"email": email, "code": code}))
}

func TestACodeOnlyWorksWithTheEmailItWasSentTo(t *testing.T) {
	mail := &outbox{}
	h := authHarness(t, mail, nil)
	email := uuid.NewString() + "@example.com"
	require.Equal(t, http.StatusAccepted, h.do(http.MethodPost, "/v1/auth/email/link", "", map[string]string{"email": email}).Code)
	_, code := mail.last(t)
	assert.Equal(t, http.StatusUnauthorized, h.verifyCode(map[string]string{"email": "other-" + email, "code": code}))
	assert.Equal(t, http.StatusOK, h.verifyCode(map[string]string{"email": email, "code": code}))
}

func TestVerifyNeedsATokenOrAnEmailAndCode(t *testing.T) {
	h := authHarness(t, &outbox{}, nil)
	rec := h.do(http.MethodPost, "/v1/auth/email/verify", "", map[string]string{})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Equal(t, "Or email and code.", (*decode[api.ErrorResponse](t, rec).Details)["token"])
	rec = h.do(http.MethodPost, "/v1/auth/email/verify", "", map[string]string{"email": "a@b.test", "code": "12345"})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.Equal(t, "Six digits.", (*decode[api.ErrorResponse](t, rec).Details)["code"])
}

// AUTH-005 over HTTP.

func TestGoogleSignInTwiceIsOneUserAndAForgedTokenIs401(t *testing.T) {
	h := authHarness(t, nil, fixedGoogle{subject: uuid.NewString()})
	first := h.do(http.MethodPost, "/v1/auth/google", "", map[string]string{"idToken": "good"})
	require.Equal(t, http.StatusOK, first.Code)
	second := h.do(http.MethodPost, "/v1/auth/google", "", map[string]string{"idToken": "good"})
	assert.Equal(t, decode[api.Session](t, first).UserId, decode[api.Session](t, second).UserId)
	me := decode[api.Me](t, h.do(http.MethodGet, "/v1/me", decode[api.Session](t, first).Token, nil))
	assert.Equal(t, "Gee", *me.DisplayName)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodPost, "/v1/auth/google", "", map[string]string{"idToken": "forged"}).Code)
}

func TestGoogleWithoutClientIDsIs503(t *testing.T) {
	h := authHarness(t, nil, nil)
	rec := h.do(http.MethodPost, "/v1/auth/google", "", map[string]string{"idToken": "good"})
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "google_unavailable", decode[api.ErrorResponse](t, rec).Code)
}

func TestLinkingAddsGoogleToTheAppleAccount(t *testing.T) {
	h := authHarness(t, nil, fixedGoogle{subject: uuid.NewString()})
	apple := h.signInApple(nil)
	rec := h.do(http.MethodPost, "/v1/me/identities/google", apple.Token, map[string]string{"idToken": "good"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	me := decode[api.Me](t, rec)
	assert.ElementsMatch(t, []api.MeProviders{"apple", "google"}, me.Providers)
	assert.Equal(t, "g@example.com", *me.Email, "Google's email comes before Apple's")
	assert.Equal(t, http.StatusOK, h.do(http.MethodPost, "/v1/me/identities/google", apple.Token, map[string]string{"idToken": "good"}).Code, "linking again is a no-op")

	viaGoogle := decode[api.Session](t, h.do(http.MethodPost, "/v1/auth/google", "", map[string]string{"idToken": "good"}))
	assert.Equal(t, apple.UserId, viaGoogle.UserId, "Google now signs in to the Apple account")
}

func TestAGoogleAccountOnAnotherUserIs409NeverAMerge(t *testing.T) {
	h := authHarness(t, nil, fixedGoogle{subject: uuid.NewString()})
	require.Equal(t, http.StatusOK, h.do(http.MethodPost, "/v1/auth/google", "", map[string]string{"idToken": "good"}).Code)
	apple := h.signInApple(nil)
	rec := h.do(http.MethodPost, "/v1/me/identities/google", apple.Token, map[string]string{"idToken": "good"})
	assert.Equal(t, http.StatusConflict, rec.Code)
	assert.Equal(t, "identity_taken", decode[api.ErrorResponse](t, rec).Code)
}

func TestSignInEmailLimitIsPerVisitorBehindTheWorker(t *testing.T) {
	const secret = "s3cret-for-tests"
	h := authHarness(t, &outbox{}, nil, func(d *Deps) { d.Config.WebClientSecret = secret })
	send := func(headers map[string]string) int {
		headers["Content-Type"] = "application/json"
		return h.send(http.MethodPost, "/v1/auth/email/link", headers, `{"email":"`+uuid.NewString()+`@example.com"}`).Code
	}
	worker := func() map[string]string { return map[string]string{"X-Forwarded-For": "104.28.0.1"} }
	for range 20 {
		require.Equal(t, http.StatusAccepted, send(worker()))
	}
	assert.Equal(t, http.StatusTooManyRequests, send(worker()))

	visitor := worker()
	visitor["X-Aaru-Visitor"] = "198.51.100.7"
	visitor["X-Aaru-Web-Secret"] = secret
	assert.Equal(t, http.StatusAccepted, send(visitor))

	forged := worker()
	forged["X-Aaru-Visitor"] = "198.51.100.8"
	forged["X-Aaru-Web-Secret"] = "guess"
	assert.Equal(t, http.StatusTooManyRequests, send(forged))
}
