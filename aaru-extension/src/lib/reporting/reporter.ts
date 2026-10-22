import {
  BrowserClient,
  Scope,
  createTransport,
  dedupeIntegration,
  defaultStackParser,
  eventFiltersIntegration,
  linkedErrorsIntegration,
} from '@sentry/browser'
import type { BrowserOptions } from '@sentry/browser'
import { BUILD_REPORTING, OFF, reporterFrom } from './config'
import type { ContentError, Reporter, ReportingConfig } from './config'
import { dropBreadcrumb, scrubEvent, scrubUrl } from './scrub'

/**
 * The background's Sentry client, the only one in the extension. Per Sentry's guidance for
 * shared environments it is never `Sentry.init`: a `BrowserClient` on its own `Scope`, with
 * no integration that wraps timers, listeners, `fetch`, `console` or `history`. The
 * background adds its own `error` / `unhandledrejection` listeners and reports through
 * `capture`; content scripts' errors arrive through `captureContent`.
 */

/** Hands one serialized envelope on; answers with the HTTP status, when there was one. */
export type SendEnvelope = (
  body: string,
) => Promise<{ statusCode?: number } | undefined>

export type BackgroundReporter = Reporter & {
  /** A content script's error, tagged with the origin of the page it ran on. */
  captureContent: (error: ContentError, pageUrl: string | undefined) => void
}

/** Sentry's own collection switches, all off. */
const NO_DATA_COLLECTION: NonNullable<BrowserOptions['dataCollection']> = {
  userInfo: false,
  cookies: false,
  httpHeaders: false,
  httpBodies: [],
  urlQueryParams: false,
  stackFrameVariables: false,
}

export function createReporter(options: {
  send: SendEnvelope
  version: string
  config?: ReportingConfig
}): BackgroundReporter {
  const config = options.config ?? BUILD_REPORTING
  if (!config.dsn) return { ...OFF, captureContent: () => {} }

  // Built on the first error.
  let scope: Scope | null = null
  const ready = (): Scope => {
    if (scope) return scope
    const client = new BrowserClient({
      dsn: config.dsn,
      environment: config.environment,
      release: config.release ?? `aaru-extension@${options.version}`,
      transport: (transportOptions) =>
        createTransport(transportOptions, async (request) => {
          const body =
            typeof request.body === 'string'
              ? request.body
              : new TextDecoder().decode(request.body)
          const answer = await options.send(body)
          return { statusCode: answer?.statusCode }
        }),
      stackParser: defaultStackParser,
      integrations: [
        eventFiltersIntegration(),
        linkedErrorsIntegration(),
        dedupeIntegration(),
      ],
      tracesSampleRate: 0,
      sendClientReports: false,
      maxBreadcrumbs: 0,
      dataCollection: NO_DATA_COLLECTION,
      beforeSend: scrubEvent,
      beforeBreadcrumb: dropBreadcrumb,
    })
    const created = new Scope()
    created.setClient(client)
    client.init()
    scope = created
    return created
  }

  const send = (tags: Record<string, string>, error: unknown) => {
    const forThis = ready().clone()
    forThis.setTags(tags)
    forThis.captureException(error)
  }
  const reporter = reporterFrom((error) =>
    send({ context: 'background' }, error),
  )
  return {
    ...reporter,
    captureContent: (report, pageUrl) => {
      try {
        const site = originOf(pageUrl)
        send({ context: 'content', ...(site ? { site } : {}) }, asError(report))
      } catch {
        // Best effort, like every report.
      }
    },
  }
}

/** Rebuilds an Error so Sentry parses the content script's own stack. */
function asError(report: ContentError): Error {
  const error = new Error(report.message)
  error.name = report.name
  error.stack = report.stack ?? `${report.name}: ${report.message}`
  return error
}

/** Only the origin of the page a content script ran on, never its path. */
function originOf(url: string | undefined): string | undefined {
  if (!url) return undefined
  try {
    return new URL(scrubUrl(url)).origin
  } catch {
    return undefined
  }
}

/** The ingest URL for a DSN: `https://KEY@HOST/PROJECT` → `https://HOST/api/PROJECT/envelope/`. */
export function envelopeEndpoint(dsn: string): string | null {
  try {
    const url = new URL(dsn)
    const segments = url.pathname.split('/').filter(Boolean)
    const project = segments.pop()
    if (!url.username || !project) return null
    const path = segments.length ? `/${segments.join('/')}` : ''
    const query = new URLSearchParams({
      sentry_version: '7',
      sentry_key: url.username,
    })
    return `${url.protocol}//${url.host}${path}/api/${project}/envelope/?${query}`
  } catch {
    return null
  }
}

/** The most one envelope may weigh; an error event is a few KB. */
export const ENVELOPE_MAX_BYTES = 200_000
