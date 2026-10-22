import type { CloudflareOptions } from '@sentry/cloudflare'
import { PRIVATE_DATA_COLLECTION, scrubBreadcrumb, scrubEvent } from './scrub'

/**
 * Error reporting in the Worker (SSR and server functions): errors only, scrubbed like the
 * browser's (docs/privacy.md). `SENTRY_DSN` is a var per environment in wrangler.jsonc; empty
 * means src/server.ts never wraps the handler, so nothing initialises.
 */
type ReportingEnv = { SENTRY_DSN?: string; CHANNEL?: string }

/**
 * The Worker integrations that only report. Not the defaults: no fetch breadcrumbs, no console
 * capture, no request body capture. RequestData stays for the page's address and method;
 * `dataCollection` keeps its cookies, headers and query out, and `scrubEvent` checks again.
 */
const KEPT_INTEGRATIONS = new Set([
  'Dedupe',
  'EventFilters',
  'FunctionToString',
  'LinkedErrors',
  'RequestData',
])

export function serverReportingOptions(
  env: ReportingEnv,
  release: string | undefined,
): CloudflareOptions | undefined {
  if (!env.SENTRY_DSN) return undefined
  return {
    dsn: env.SENTRY_DSN,
    environment: env.CHANNEL || 'production',
    release,
    tracesSampleRate: 0,
    sendClientReports: false,
    dataCollection: PRIVATE_DATA_COLLECTION,
    integrations: (defaults) =>
      defaults.filter((integration) => KEPT_INTEGRATIONS.has(integration.name)),
    beforeSend: scrubEvent,
    beforeBreadcrumb: scrubBreadcrumb,
  }
}
