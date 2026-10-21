import {
  createCsrfMiddleware,
  createMiddleware,
  createStart,
} from '@tanstack/solid-start'

const CANONICAL_HOST = 'aaruapp.com'

/**
 * Response headers for every page and server function. No script CSP yet: the sign-in page
 * loads Apple's and Google's SDKs and Sentry, and a policy that misses one silently breaks
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
 * Server functions answer only this origin. Start adds this check itself only when an app has
 * no `src/start.ts`; with one, it is ours to add. The session cookie is SameSite=Lax, which
 * still lets another aaruapp.com subdomain call in; the Sec-Fetch-Site / Origin check does not.
 */
const sameOriginServerFns = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === 'serverFn',
})

export const startInstance = createStart(() => ({
  // Headers first, so a refused request still carries them.
  requestMiddleware: [securityHeaders, sameOriginServerFns],
}))
