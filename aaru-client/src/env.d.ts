/// <reference types="vite/client" />

// Build-time values from vite.config.ts (wrangler.jsonc vars and CI). Empty DSN = no reporting.
interface ImportMetaEnv {
  readonly VITE_SENTRY_DSN?: string
  readonly VITE_SENTRY_ENVIRONMENT?: string
  readonly VITE_SENTRY_RELEASE?: string
}
