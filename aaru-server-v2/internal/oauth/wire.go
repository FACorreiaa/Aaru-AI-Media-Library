package oauth

import (
	"aaru-go-api/internal/config"

	"github.com/jackc/pgx/v5/pgxpool"
)

// FromConfig builds the front door from PUBLIC_BASE_URL, WEB_BASE_URL and OAUTH_COOKIE_DOMAIN.
func FromConfig(cfg *config.App, pool *pgxpool.Pool) *Service {
	return NewService(NewStore(pool), Settings{
		PublicBaseURL: cfg.PublicBaseURL, WebBaseURL: cfg.WebBaseURL, CookieDomain: cfg.OAuthCookieDomain,
	})
}
