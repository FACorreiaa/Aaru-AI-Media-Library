import {
  breadcrumbsIntegration,
  browserApiErrorsIntegration,
  captureException,
  dedupeIntegration,
  eventFiltersIntegration,
  functionToStringIntegration,
  globalHandlersIntegration,
  httpContextIntegration,
  init,
  linkedErrorsIntegration,
} from '@sentry/browser'
import { PRIVATE_DATA_COLLECTION, scrubBreadcrumb, scrubEvent } from './scrub'
import type { BrowserReportingConfig } from './browser'

/**
 * The Sentry chunk, loaded by browser.ts with `import()`. Named imports only, so the bundle
 * carries what reports an error and none of replay, feedback, tracing or logs.
 */
export function startSentry(
  config: BrowserReportingConfig,
): (error: unknown) => void {
  init({
    dsn: config.dsn,
    environment: config.environment,
    release: config.release,
    tracesSampleRate: 0,
    sendClientReports: false,
    dataCollection: PRIVATE_DATA_COLLECTION,
    // Not the defaults: no console capture, no session pings, no locale context, and
    // breadcrumbs for navigation only.
    defaultIntegrations: false,
    integrations: [
      eventFiltersIntegration(),
      functionToStringIntegration(),
      browserApiErrorsIntegration(),
      globalHandlersIntegration(),
      linkedErrorsIntegration(),
      dedupeIntegration(),
      httpContextIntegration(),
      breadcrumbsIntegration({
        dom: false,
        fetch: false,
        xhr: false,
        sentry: false,
        history: true,
      }),
    ],
    beforeSend: scrubEvent,
    beforeBreadcrumb: scrubBreadcrumb,
  })
  return (error) => void captureException(error)
}
