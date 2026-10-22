import {
  createCsrfMiddleware,
  createMiddleware,
  createStart,
} from '@tanstack/solid-start'
import { browserQueryClient } from './integrations/tanstack-query/provider'
import { SESSION_KEY } from './lib/session/query'
import {
  reportFunctionErrors,
  reportRequestErrors,
} from './lib/observability/middleware'

const CANONICAL_HOST = 'aaruapp.com'

/**
 * Response headers for every page and server function. No script CSP yet: the sign-in page
 * loads Apple's and Google's SDKs and Sentry (when a DSN is set), and a policy that misses one silently breaks
 * sign-in. frame-ancestors is safe to pin now.
 */
const SECURITY_HEADERS: Record<string, string> = {
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy':
    'geolocation=(), microphone=(), camera=(), payment=(), usb=()',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy': "frame-ancestors 'none'",
}

const securityHeaders = createMiddleware().server(async ({ request, next }) => {
  // One origin: www is a permanent redirect to the apex, path and query kept.
  const url = new URL(request.url)
  if (url.hostname === `www.${CANONICAL_HOST}`) {
    url.hostname = CANONICAL_HOST
    return Response.redirect(url.toString(), 301)
  }
  const result = await next()
  // A copy, because some responses have immutable headers (`Response.redirect`, fetched
  // upstream responses) and setting one on them throws, turning the page into a 500.
  const response = new Response(result.response.body, result.response)
  // Plain http (local dev) must not pin HSTS on localhost.
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    if (name === 'Strict-Transport-Security' && url.protocol !== 'https:')
      continue
    response.headers.set(name, value)
  }
  return { ...result, response }
})

/**
 * Every POST is a write (or one-off work like a search), so after one the browser's cached
 * reads count as old: the next page or Back asks the server again instead of showing what was
 * there before the change. Nothing refetches right away. The session stays cached; signing in
 * and out manage it themselves.
 */
const staleAfterWrite = createMiddleware({ type: 'function' }).client(
  async ({ method, next }) => {
    const result = await next()
    if (method === 'POST')
      void browserQueryClient()?.invalidateQueries({
        predicate: (query) => query.queryKey[0] !== SESSION_KEY[0],
        refetchType: 'none',
      })
    return result
  },
)

/**
 * Server functions answer only this origin. Start adds this check itself only when an app has
 * no `src/start.ts`; with one, it is ours to add. The session cookie is SameSite=Lax, which
 * still lets another aaruapp.com subdomain call in; the Sec-Fetch-Site / Origin check does not.
 */
const sameOriginServerFns = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === 'serverFn',
})

export const startInstance = createStart(() => ({
  // Headers first, so a refused request still carries them. Error reporting next, so it
  // sees what the page or server function throws before Start turns it into a response.
  requestMiddleware: [
    securityHeaders,
    reportRequestErrors,
    sameOriginServerFns,
  ],
  functionMiddleware: [reportFunctionErrors, staleAfterWrite],
}))
