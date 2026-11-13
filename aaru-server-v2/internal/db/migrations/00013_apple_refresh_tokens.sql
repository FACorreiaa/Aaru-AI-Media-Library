-- Sign in with Apple's refresh tokens (AUTH-006). App Store rule 5.1.1(v): deleting an account
-- must revoke the user's Sign in with Apple tokens, and Apple revokes only a token it is shown.
-- One row per user and client id (the app's bundle id, the beta's, the web's Services ID): a
-- token is revoked with the client id it was issued to. `refresh_token` is sealed with
-- APPLE_SIGNIN_TOKEN_KEY (AES-256-GCM), never plain. The rows go with the user.

-- +goose Up
CREATE TABLE apple_refresh_tokens (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id text NOT NULL,
    refresh_token text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, client_id)
);

-- +goose Down
DROP TABLE apple_refresh_tokens;
