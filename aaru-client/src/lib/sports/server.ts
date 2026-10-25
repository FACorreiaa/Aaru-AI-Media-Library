import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import { validTimeZone } from '../timezone'
import type {
  SportEntity,
  SportEntityList,
  SportEventDetail,
  SportFavorites,
  SportSchedule,
  SportSettings,
} from './model'

// SPT-003 on the web: the Worker forwards to `/v1/sports/*`, `/v1/me/sport-follows` and
// `/v1/me/sport-settings`, nothing more. Reads are GETs, so they never mark the page's cached
// reads as old; following and the country are writes.

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

const kind = z.enum(['league', 'team', 'player'])
const providerId = z.string().trim().min(1).max(64)

export const saveSportSettings = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      watchCountryCode: z
        .string()
        .regex(/^[A-Z]{2}$/)
        .nullable(),
    }),
  )
  .handler(async ({ data }): Promise<SportSettings> =>
    check(
      await api(sessionToken()).PUT('/v1/me/sport-settings', { body: data }),
      'That country was not saved.',
    ),
  )

/** The first-run picks: Premier League, La Liga, NBA, NFL, UFC, WWE… */
export const getSportSuggestions = createServerFn({ method: 'GET' }).handler(
  async (): Promise<SportEntityList> =>
    check(
      await api(sessionToken()).GET('/v1/sports/suggested'),
      'Sports could not be loaded.',
    ),
)

export const searchSports = createServerFn({ method: 'GET' })
  .validator(
    z.object({ q: z.string().trim().min(2).max(100), kind: kind.optional() }),
  )
  .handler(async ({ data }): Promise<SportEntityList> =>
    check(
      await api(sessionToken()).GET('/v1/sports/search', {
        params: { query: { q: data.q, kind: data.kind } },
      }),
      'Sports could not be searched right now.',
    ),
  )

export const getSportFavorites = createServerFn({ method: 'GET' }).handler(
  async (): Promise<SportFavorites> =>
    check(
      await api(sessionToken()).GET('/v1/sports/favorites'),
      'Your favorites could not be loaded.',
    ),
)

export const getSportSchedule = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      tz: z
        .string()
        .max(64)
        .refine((tz) => validTimeZone(tz) !== null),
    }),
  )
  .handler(async ({ data }): Promise<SportSchedule> =>
    check(
      await api(sessionToken()).GET('/v1/sports/schedule', {
        params: { query: { date: data.date, tz: data.tz } },
      }),
      'The schedule could not be loaded.',
    ),
  )

export const getSportEvent = createServerFn({ method: 'GET' })
  .validator(z.object({ id: providerId }))
  .handler(async ({ data }): Promise<SportEventDetail> =>
    check(
      await api(sessionToken()).GET('/v1/sports/events/{id}', {
        params: { path: { id: data.id } },
      }),
      'That event could not be loaded.',
    ),
  )

export const followSport = createServerFn({ method: 'POST' })
  .validator(z.object({ kind, id: providerId }))
  .handler(async ({ data }): Promise<SportEntity> => {
    const result = await api(sessionToken()).PUT(
      '/v1/me/sport-follows/{kind}/{providerId}',
      { params: { path: { kind: data.kind, providerId: data.id } } },
    )
    if (
      result.response.status === 409 &&
      result.error?.code === 'too_many_follows'
    )
      throw new Error('You follow 100 already. Unfollow one to add another.')
    return check(result, 'That was not followed.')
  })

export const unfollowSport = createServerFn({ method: 'POST' })
  .validator(z.object({ kind, id: providerId }))
  .handler(async ({ data }): Promise<void> => {
    const { error, response } = await api(sessionToken()).DELETE(
      '/v1/me/sport-follows/{kind}/{providerId}',
      { params: { path: { kind: data.kind, providerId: data.id } } },
    )
    if (response.status === 401) sessionRejected()
    if (!response.ok)
      throw new Error(errorMessage(error, 'That was not unfollowed.'))
  })
