import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// SCR-003 on the web: connect Aaru's Stremio addon, over the same `/v1/agent/tokens` routes as
// the Apple apps.

export type AgentToken = components['schemas']['AgentToken']
export type StremioConnection = components['schemas']['AgentTokenCreated']

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** The user's live Stremio links. Stremio is the only token kind so far. */
export const listStremio = createServerFn({ method: 'GET' }).handler(
  async (): Promise<AgentToken[]> =>
    check(
      await api(sessionToken()).GET('/v1/agent/tokens'),
      'Your Stremio links could not be loaded.',
    ).items,
)

/** Mints a link. The answer carries the install links; they are shown once. */
export const connectStremio = createServerFn({ method: 'POST' })
  .validator(z.object({ allowLibraryWrites: z.boolean() }))
  .handler(async ({ data }): Promise<StremioConnection> =>
    check(
      await api(sessionToken()).POST('/v1/agent/tokens', {
        body: { kind: 'stremio', allowLibraryWrites: data.allowLibraryWrites },
      }),
      'Stremio could not be connected.',
    ),
  )

export const revokeStremio = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE('/v1/agent/tokens/{id}', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok)
      throw new Error(
        errorMessage(result.error, 'That Stremio link was not revoked.'),
      )
  })
