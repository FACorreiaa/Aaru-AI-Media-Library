import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { OnAirGuide } from '../discover/onAir'
import type { SeasonPage } from '../discover/season'
import type { DiscoverRow, UpNext } from './model'
import type { RankedTonight } from './tonight'

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

/** DISC-003: this week's shows by channel; `region` (never stored) adds where they stream. */
export const getDiscoverOnAir = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      region: z
        .string()
        .regex(/^[A-Z]{2}$/)
        .optional(),
    }),
  )
  .handler(async ({ data }): Promise<OnAirGuide> => {
    const {
      data: guide,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/discover/on-air', {
      params: { query: data },
    })
    if (response.status === 401) sessionRejected()
    if (!guide)
      throw new Error(errorMessage(error, 'On air could not be loaded.'))
    return guide
  })

/** AG-005: Tonight as the server ranks it, for the viewer's local day. */
export const getTonight = createServerFn({ method: 'GET' })
  .validator(z.object({ tz: z.string().min(1).max(64) }))
  .handler(async ({ data }): Promise<RankedTonight> => {
    const {
      data: tonight,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/tonight', {
      params: { query: { tz: data.tz } },
    })
    if (response.status === 401) sessionRejected()
    if (!tonight)
      throw new Error(errorMessage(error, 'Tonight could not be loaded.'))
    return tonight
  })

/** "Not tonight" hides a pick until the local day ends; "rejected" (not for me) for longer. */
export const sendTonightFeedback = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      id: z.string().uuid(),
      verdict: z.enum(['rejected', 'not_tonight']),
      tz: z.string().min(1).max(64),
    }),
  )
  .handler(async ({ data }) => {
    const { error, response } = await api(sessionToken()).POST(
      '/v1/tonight/{id}/feedback',
      {
        params: { path: { id: data.id }, query: { tz: data.tz } },
        body: { verdict: data.verdict },
      },
    )
    if (response.status === 401) sessionRejected()
    if (!response.ok)
      throw new Error(errorMessage(error, 'That could not be set aside.'))
  })

/** The Undo after "Not tonight" or "Not for me": today's verdict on the item is taken back. */
export const clearTonightFeedback = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      id: z.string().uuid(),
      tz: z.string().min(1).max(64),
    }),
  )
  .handler(async ({ data }) => {
    const { error, response } = await api(sessionToken()).DELETE(
      '/v1/tonight/{id}/feedback',
      { params: { path: { id: data.id }, query: { tz: data.tz } } },
    )
    if (response.status === 401) sessionRejected()
    if (!response.ok)
      throw new Error(errorMessage(error, 'That could not be undone.'))
  })
