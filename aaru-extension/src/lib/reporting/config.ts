/**
 * Error reporting for the extension (docs/privacy.md): errors only, to the `aaru-extension`
 * Sentry project. This file holds what both sides share and imports no Sentry code, so the
 * content scripts stay small.
 */
export type ReportingConfig = {
  dsn: string
  environment: string
  release: string | undefined
}

/** The `aaru-extension` project's DSN. Public, not a secret: it can only send errors in. */
const STORE_DSN =
  'https://5a52d56dbe22c31fb68459c9de01c1ab@o4510766840872960.ingest.de.sentry.io/4512299387256913'

/**
 * From the build's environment (`WXT_SENTRY_*`). A production build reports to `STORE_DSN`
 * unless `WXT_SENTRY_DSN` says otherwise; `npm run dev` and tests report nothing. An empty DSN
 * turns it off.
 */
export const BUILD_REPORTING: ReportingConfig = {
  dsn:
    import.meta.env.WXT_SENTRY_DSN ??
    (import.meta.env.MODE === 'production' ? STORE_DSN : ''),
  environment:
    import.meta.env.WXT_SENTRY_ENVIRONMENT ||
    (import.meta.env.MODE === 'development' ? 'development' : 'production'),
  release: import.meta.env.WXT_SENTRY_RELEASE || undefined,
}

/** What a content script hands the background about one error: no page, no state. */
export type ContentError = { name: string; message: string; stack?: string }

export type Reporter = {
  capture: (error: unknown) => void
  guard: <TArgs extends unknown[], TResult>(
    fn: (...args: TArgs) => TResult,
  ) => (...args: TArgs) => TResult | undefined
}

export const OFF: Reporter = {
  capture: () => {},
  guard: (fn) => fn,
}

/** Builds `guard` on top of a `capture`. Reporting never breaks the extension. */
export function reporterFrom(capture: (error: unknown) => void): Reporter {
  const safe = (error: unknown) => {
    try {
      capture(error)
    } catch {
      // Nothing to do: the error was the extension's, the report is best effort.
    }
  }
  return {
    capture: safe,
    guard:
      (fn) =>
      (...args) => {
        try {
          return fn(...args)
        } catch (error) {
          safe(error)
          return undefined
        }
      },
  }
}

const MESSAGE_MAX = 1_000
const STACK_MAX = 10_000

/** An error as a content script sends it: name, message and stack, capped. */
export function toContentError(error: unknown): ContentError {
  if (error instanceof Error)
    return {
      name: error.name.slice(0, 100),
      message: error.message.slice(0, MESSAGE_MAX),
      stack: error.stack?.slice(0, STACK_MAX),
    }
  return { name: 'Error', message: String(error).slice(0, MESSAGE_MAX) }
}

/** Reads a ContentError back from a runtime message; null when it is not one. */
export function parseContentError(value: unknown): ContentError | null {
  if (typeof value !== 'object' || value === null) return null
  const { name, message, stack } = value as Record<string, unknown>
  if (typeof name !== 'string' || typeof message !== 'string') return null
  return {
    name: name.slice(0, 100),
    message: message.slice(0, MESSAGE_MAX),
    stack: typeof stack === 'string' ? stack.slice(0, STACK_MAX) : undefined,
  }
}
