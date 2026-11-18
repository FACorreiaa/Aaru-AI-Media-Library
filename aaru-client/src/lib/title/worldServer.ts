import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { World, WorldSummary } from './world'

// GRAPH-007. Apart from `server.ts`, which the title route loads up front: these travel with the
// World pages and the lazy strip.

/** The World a title belongs to, marked with the caller's library. `building` while the server
 * is still making it: ask again in a few seconds. */
export const loadWorld = createServerFn({ method: 'GET' })
  .validator(z.object({ titleId: z.string().uuid() }))
  .handler(async ({ data }): Promise<World> => {
    const {
      data: world,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/titles/{id}/world', {
      params: { path: { id: data.titleId } },
    })
    if (response.status === 401) sessionRejected()
    if (!world)
      throw new Error(errorMessage(error, 'This world could not be loaded.'))
    return world
  })

/** The Worlds the caller has a title in, those with something left first. */
export const loadMyWorlds = createServerFn({ method: 'GET' }).handler(
  async (): Promise<WorldSummary[]> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/me/worlds')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'Your worlds could not be loaded.'))
    return data.worlds
  },
)

/** "Add the rest": the World's titles the caller lacks, as a capture to review. Nothing is added
 * until they approve it. */
export const planWorldRest = createServerFn({ method: 'POST' })
  .validator(z.object({ titleId: z.string().uuid() }))
  .handler(async ({ data }): Promise<{ id: string }> => {
    const {
      data: job,
      error,
      response,
    } = await api(sessionToken()).POST('/v1/titles/{id}/world/plan', {
      params: { path: { id: data.titleId } },
    })
    if (response.status === 401) sessionRejected()
    if (!job)
      throw new Error(
        errorMessage(error, 'The rest of this world could not be planned.'),
      )
    return { id: job.id }
  })
