import { captureException } from '@sentry/cloudflare'
import { isNotFound, isRedirect } from '@tanstack/solid-router'
import { createMiddleware } from '@tanstack/solid-start'

/**
 * Start catches what a page or server function throws and turns it into a response, so the
 * Worker wrapper (src/server.ts) never sees it. These report it on the way past and rethrow;
 * redirects and not-founds are control flow, not errors. Without a DSN there is no Sentry
 * client and `captureException` does nothing.
 */
function reportServerError(error: unknown): void {
  if (isRedirect(error) || isNotFound(error)) return
  captureException(error)
}

export const reportRequestErrors = createMiddleware().server(
  async ({ next }) => {
    try {
      return await next()
    } catch (error) {
      reportServerError(error)
      throw error
    }
  },
)

export const reportFunctionErrors = createMiddleware({
  type: 'function',
}).server(async ({ next }) => {
  try {
    return await next()
  } catch (error) {
    reportServerError(error)
    throw error
  }
})
