import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { Discover } from './model'

// Discover on the web: the same `/v1/discover` the Apple apps call. One section (Home's teaser)
// or all of them. A section whose catalog failed is simply missing; all failing is an error.

export const getDiscover = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      section: z
        .enum([
          'trending',
          'upcoming_movies',
          'new_shows',
          'on_the_air',
          'anime_season',
          'anime_next_season',
        ])
        .optional(),
    }),
  )
  .handler(async ({ data }): Promise<Discover> => {
    const {
      data: discover,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/discover', {
      params: { query: { section: data.section } },
    })
    if (response.status === 401) sessionRejected()
    if (!discover)
      throw new Error(
        errorMessage(error, 'Discover is not available right now.'),
      )
    return discover
  })
