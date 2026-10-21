import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { SeasonPage } from '../discover/season'
import type { DiscoverRow, UpNext } from './model'

// APP-009 on the web: Continue watching and Start watching in one call, as the Apple apps'
// Home gets them.

export const getUpNext = createServerFn({ method: 'GET' }).handler(
  async (): Promise<UpNext> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/up-next')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'Up next could not be loaded.'))
    return data
  },
)

/** DISC-001: the public rows under the user's own, the same for everyone. */
export const getDiscover = createServerFn({ method: 'GET' }).handler(
  async (): Promise<DiscoverRow[]> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/discover')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'Discover could not be loaded.'))
    return data.rows
  },
)

/** DISC-002: one page of one season for the Seasons view, the same for everyone. */
export const getDiscoverSeason = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      kind: z.enum(['anime', 'shows_new', 'shows_returning', 'movies']),
      season: z.enum(['winter', 'spring', 'summer', 'fall']),
      year: z.number().int().min(1970).max(2200),
      page: z.number().int().min(1).max(20).optional(),
    }),
  )
  .handler(async ({ data }): Promise<SeasonPage> => {
    const {
      data: page,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/discover/season', {
      params: { query: data },
    })
    if (response.status === 401) sessionRejected()
    if (!page)
      throw new Error(errorMessage(error, 'This season could not be loaded.'))
    return page
  })
