import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { TitleWatch } from './watch'

// Apart from `server.ts`, which the title route loads up front: this one travels with the lazy
// "Where to watch" section.

/** CAT-014: where a film or show can be watched in the viewer's region. The region is sent for
 * this request only. Empty lists when there is nothing to show. */
export const loadWatch = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      titleId: z.string().uuid(),
      region: z.string().regex(/^[A-Z]{2}$/),
    }),
  )
  .handler(async ({ data }): Promise<TitleWatch> => {
    const {
      data: places,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/titles/{id}/watch', {
      params: { path: { id: data.titleId }, query: { region: data.region } },
    })
    if (response.status === 401) sessionRejected()
    if (!places)
      throw new Error(
        errorMessage(error, 'Where to watch could not be loaded.'),
      )
    return places
  })
