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
  })
}
