import { env } from 'cloudflare:workers'
import { withSentry } from '@sentry/cloudflare'
import handler, { createServerEntry } from '@tanstack/solid-start/server-entry'
import { serverReportingOptions } from './lib/observability/server'

/**
 * The Worker entry (wrangler.jsonc `main`): Start's own handler, wrapped for error reporting
 * when this environment has a `SENTRY_DSN`. Without one the handler is exported as it is and
 * the Sentry SDK never initialises.
 */
const entry = createServerEntry({
  fetch: (request) => handler.fetch(request),
})

const release = import.meta.env.VITE_SENTRY_RELEASE || undefined

export default env.SENTRY_DSN
  ? withSentry(
      (workerEnv: Env) => serverReportingOptions(workerEnv, release),
      entry as ExportedHandler<Env>,
    )
  : entry
