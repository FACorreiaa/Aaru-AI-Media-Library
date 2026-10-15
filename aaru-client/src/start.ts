import { createMiddleware, createStart } from '@tanstack/solid-start'

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
  // Plain http (local dev) must not pin HSTS on localhost.
  for (const [name, value] of Object.entries(SECURITY_HEADERS)) {
    if (name === 'Strict-Transport-Security' && url.protocol !== 'https:')
      continue
    result.response.headers.set(name, value)
  }
  return result
})

export const startInstance = createStart(() => ({
  requestMiddleware: [securityHeaders],
}))
