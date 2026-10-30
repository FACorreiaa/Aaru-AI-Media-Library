package auth

import (
	"aaru-go-api/internal/config"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
)

// FromConfig builds sign-in and agent tokens as the Swift server wired them:
// email sign-in only with RESEND_API_KEY, Google only with GOOGLE_CLIENT_IDS.
// client is the outbound HTTP client (Apple's and Google's keys, Resend); nil uses a default.
func FromConfig(cfg *config.App, pool *pgxpool.Pool, client *http.Client) (*Service, *AgentTokenService) {
	apple := AppleVerifier{Audiences: cfg.AppleAudiences, JWKS: NewJWKSCache(client, AppleKeysURL)}
	var magicLinks *MagicLinks
	if cfg.Email != nil {
		magicLinks = &MagicLinks{
			Sender:      NewResendSender(client, cfg.Email.ResendAPIKey, cfg.Email.From),
			LinkBaseURL: cfg.Email.LinkBaseURL,
		}
	}
	var google GoogleVerifying
	if len(cfg.GoogleAudiences) > 0 {
		google = GoogleVerifier{Audiences: cfg.GoogleAudiences, JWKS: NewJWKSCache(client, GoogleKeysURL)}
	}
	return NewService(NewStore(pool), apple, magicLinks, google), NewAgentTokenService(pool, cfg.PublicBaseURL)
}
