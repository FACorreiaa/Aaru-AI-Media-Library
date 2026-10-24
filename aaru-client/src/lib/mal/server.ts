import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// SCR-005 on the web: connect MyAnimeList, over the same `/v1/connections/mal` routes as the
// Apple apps. The server pushes anime progress; the web only connects and disconnects.

export type MALConnection = components['schemas']['MALConnection']

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** Whether this account has connected MyAnimeList, as whom, and whether MAL still accepts it. */
export const getMALConnection = createServerFn({ method: 'GET' }).handler(
  async (): Promise<MALConnection> =>
    check(
      await api(sessionToken()).GET('/v1/connections/mal'),
      'Your MyAnimeList connection could not be loaded.',
    ),
)

/**
 * Starts a MyAnimeList sign-in (PKCE, held by the server) and returns MAL's page to open. MAL
 * sends the browser back to `returnTo` with `?mal=connected|denied|failed`; the server only
 * accepts Aaru's own origins.
 */
export const connectMAL = createServerFn({ method: 'POST' })
  .validator(z.object({ returnTo: z.string().url().max(500) }))
  .handler(
    async ({ data }): Promise<string> =>
      check(
        await api(sessionToken()).POST('/v1/connections/mal/connect', {
          body: { returnTo: data.returnTo },
        }),
        'MyAnimeList could not be reached. Try again in a minute.',
      ).authorizeUrl,
  )

/** Forgets the tokens. Nothing more is pushed; both lists stay as they are. */
export const disconnectMAL = createServerFn({ method: 'POST' }).handler(
  async () => {
    const result = await api(sessionToken()).DELETE('/v1/connections/mal')
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok) {
      throw new Error(
        errorMessage(
          result.error,
          'MyAnimeList was not disconnected. Try again.',
        ),
      )
    }
  },
)
