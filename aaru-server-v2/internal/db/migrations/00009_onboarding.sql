-- First-run onboarding (ONB-001): when an account finished or skipped the flow, and which. A new
-- account starts with onboarded_at NULL and sees the flow; every account made before it shipped is
-- backfilled as onboarded at its creation, so only new accounts ever see it.

-- +goose Up
ALTER TABLE users
    ADD COLUMN onboarded_at timestamptz,
    ADD COLUMN onboarding_skipped boolean NOT NULL DEFAULT false;

UPDATE users SET onboarded_at = created_at;

-- +goose Down
ALTER TABLE users
    DROP COLUMN onboarding_skipped,
    DROP COLUMN onboarded_at;
