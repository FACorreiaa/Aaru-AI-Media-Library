import createClient from 'openapi-fetch'
import { env } from 'cloudflare:workers'
import type { paths } from './schema'

/**
 * The `/v1` client, server-side only. Types are generated from the server's openapi.yaml
 * (`npm run api:generate`), the same spec the Apple apps' AaruAPI comes from.
 */
export function api(token?: string) {
  return createClient<paths>({
    baseUrl: env.API_BASE_URL,
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
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

export const UNREACHABLE =
  'Aaru could not reach the server. Try again in a moment.'
