/**
 * Error reporting in the browser: errors and crashes only, no tracing, replay, profiling,
 * feedback, sessions or console capture (docs/privacy.md). The SDK is its own chunk (sdk.ts),
 * fetched after hydration and only when the build has a DSN, so first paint never waits for
 * it and a build without a DSN never downloads it.
 */
export type BrowserReportingConfig = {
  dsn: string
  environment: string
  release: string | undefined
}

/** Set at build time by vite.config.ts, from wrangler.jsonc's `SENTRY_DSN` and `CHANNEL`. */
export const BUILD_CONFIG: BrowserReportingConfig = {
  dsn: import.meta.env.VITE_SENTRY_DSN ?? '',
  environment: import.meta.env.VITE_SENTRY_ENVIRONMENT || 'production',
  release: import.meta.env.VITE_SENTRY_RELEASE || undefined,
}

type Sdk = {
  startSentry: (config: BrowserReportingConfig) => (error: unknown) => void
}

/** Errors caught before the SDK arrives wait here, a few at most. */
const PENDING_MAX = 10

export function createBrowserReporter(
  config: BrowserReportingConfig,
  load: () => Promise<Sdk> = () => import('./sdk'),
) {
  let capture: ((error: unknown) => void) | null = null
  let pending: unknown[] = []
  let loading: Promise<void> | null = null

  const start = (): Promise<void> => {
    if (!config.dsn) return Promise.resolve()
    loading ??= load()
      .then((sdk) => {
        const send = sdk.startSentry(config)
        capture = send
        for (const error of pending) send(error)
        pending = []
      })
      .catch(() => {
        // The chunk did not load (offline, blocked): the app carries on without reporting.
        pending = []
      })
    return loading
  }

  const report = (error: unknown) => {
    if (!config.dsn) return
    if (capture) capture(error)
    else if (pending.length < PENDING_MAX) pending.push(error)
  }

  return { start, report }
}

const reporter = createBrowserReporter(BUILD_CONFIG)

/** Starts error reporting once the page has hydrated. A no-op without a DSN. */
export const startBrowserErrorReporting = reporter.start

/** Reports an error the app caught itself (a route's error boundary). */
export const reportBrowserError = reporter.report
