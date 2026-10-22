import createClient from 'openapi-fetch'
import { env } from 'cloudflare:workers'
import { getCookie } from '@tanstack/solid-start/server'
import { TIMEZONE_COOKIE, validTimeZone } from '../timezone'
import type { paths } from './schema'

/**
 * The `/v1` client, server-side only. Types are generated from the server's openapi.yaml
 * (`npm run api:generate`), the same spec the Apple apps' AaruAPI comes from. A signed-in call
 * carries the viewer's time zone (GAM-003), so points and streak days fall on their own day.
 */
export function api(token?: string) {
  const zone = token ? requestTimeZone() : null
  const headers: Record<string, string> = {}
  if (token) headers.Authorization = `Bearer ${token}`
  if (zone) headers['X-Timezone'] = zone
  return createClient<paths>({
    baseUrl: env.API_BASE_URL,
    headers,
    // A network failure becomes one plain message instead of a fetch stack trace.
    fetch: async (request) => {
      try {
        return await fetch(request)
      } catch {
        throw new Error(UNREACHABLE)
      }
    },
  })
}

/** The zone the shell left in its cookie; none outside a request or when it is not a zone. */
function requestTimeZone(): string | null {
  try {
    return validTimeZone(getCookie(TIMEZONE_COOKIE))
  } catch {
    return null
  }
}

export const UNREACHABLE =
  'Aaru could not reach the server. Try again in a moment.'
