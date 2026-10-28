import createClient from 'openapi-fetch'
import { env } from 'cloudflare:workers'
import { getCookie, getRequestHeader } from '@tanstack/solid-start/server'
import { TIMEZONE_COOKIE, validTimeZone } from '../timezone'
import { visitorHeaders } from './visitor'
import type { paths } from './schema'

/**
 * The `/v1` client, server-side only. Types are generated from the server's openapi.yaml
 * (`npm run api:generate`), the same spec the Apple apps' AaruAPI comes from. A signed-in call
 * carries the viewer's time zone (GAM-003), so points and streak days fall on their own day.
 * `visitor` is for the calls the API limits per address (an invite or share link's preview, a
 * sign-in email): it names the visitor, so they do not share Cloudflare's addresses with everyone.
 */
export function api(token?: string, options: { visitor?: boolean } = {}) {
  const zone = token ? requestTimeZone() : null
  const headers: Record<string, string> = options.visitor
    ? visitorHeaders(requestAddress(), webClientSecret())
    : {}
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

/** The visitor's address as Cloudflare saw it; none outside a request. */
function requestAddress(): string | null {
  try {
    return getRequestHeader('cf-connecting-ip') ?? null
  } catch {
    return null
  }
}

/** `WEB_CLIENT_SECRET`, a Worker secret (`wrangler secret put`), so it is not in the generated types. */
function webClientSecret(): string | undefined {
  return (env as { WEB_CLIENT_SECRET?: string }).WEB_CLIENT_SECRET
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
