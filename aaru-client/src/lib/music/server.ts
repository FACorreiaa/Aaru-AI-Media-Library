import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'
import { SCROBBLERS } from './model'

// MUS-007 on the web: connect a music scrobbler over the same `/v1/agent/tokens` routes as the
// Apple apps. The setup steps come from the server so both clients show the same ones.

export type AgentToken = components['schemas']['AgentToken']
export type Listen = components['schemas']['Listen']
export type MusicSetup = components['schemas']['MusicSetup']
export type MusicConnection = {
  token: AgentToken
  music: MusicSetup
}

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** The user's live scrobbler tokens, newest first. */
export const listScrobblers = createServerFn({ method: 'GET' }).handler(
  async (): Promise<AgentToken[]> =>
    check(
      await api(sessionToken()).GET('/v1/agent/tokens', {
        params: { query: { for: 'music' } },
      }),
      'Your scrobblers could not be loaded.',
    ).items,
)

/** The newest listen, or null before the first one arrives. */
export const latestListen = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Listen | null> =>
    check(
      await api(sessionToken()).GET('/v1/me/listens', {
        params: { query: { limit: 1 } },
      }),
      'Your last listen could not be loaded.',
    ).items[0] ?? null,
)

/** Mints a token for one scrobbler. The steps carry the token; they are shown once. */
export const connectScrobbler = createServerFn({ method: 'POST' })
  .validator(z.object({ scrobbler: z.enum(SCROBBLERS) }))
  .handler(async ({ data }): Promise<MusicConnection> => {
    const created = check(
      await api(sessionToken()).POST('/v1/agent/tokens', {
        body: { kind: 'music', scrobbler: data.scrobbler },
      }),
      'The scrobbler could not be connected.',
    )
    if (!created.music) throw new Error('The scrobbler could not be connected.')
    return { token: created.token, music: created.music }
  })

export const revokeScrobbler = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE('/v1/agent/tokens/{id}', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok)
      throw new Error(
        errorMessage(result.error, 'That scrobbler was not disconnected.'),
      )
  })
