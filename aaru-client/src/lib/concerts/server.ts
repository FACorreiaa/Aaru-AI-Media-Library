import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type {
  ArtistConcerts,
  ConcertPage,
  ConcertPlace,
  ConcertPlaceSetting,
} from './model'

// MUS-003 on the web: the Worker forwards to `/v1/concerts/*` and `/v1/me/concert-place`, nothing
// more. A position and a city search travel as POST bodies, so neither ever sits in a URL the
// Worker or anyone between could log.

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

const placeSchema = z.object({
  name: z.string().min(1).max(200),
  region: z.string().max(200).optional(),
  country: z.string().max(200).optional(),
  countryCode: z.string().length(2).optional(),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
})

/** The saved "Concerts near" city, and whether concerts are on at all. */
export const getConcertPlace = createServerFn({ method: 'GET' }).handler(
  async (): Promise<ConcertPlaceSetting> =>
    check(
      await api(sessionToken()).GET('/v1/me/concert-place'),
      'Your concerts city could not be loaded.',
    ),
)

export const saveConcertPlace = createServerFn({ method: 'POST' })
  .validator(placeSchema)
  .handler(async ({ data }): Promise<ConcertPlaceSetting> =>
    check(
      await api(sessionToken()).PUT('/v1/me/concert-place', { body: data }),
      'That city was not saved.',
    ),
  )

export const deleteConcertPlace = createServerFn({ method: 'POST' }).handler(
  async (): Promise<void> => {
    const { error, response } = await api(sessionToken()).DELETE(
      '/v1/me/concert-place',
    )
    if (response.status === 401) sessionRejected()
    if (!response.ok)
      throw new Error(errorMessage(error, 'That city was not removed.'))
  },
)

/** Cities matching what the user typed, best first. */
export const searchConcertPlaces = createServerFn({ method: 'POST' })
  .validator(z.object({ q: z.string().trim().min(2).max(100) }))
  .handler(
    async ({ data }): Promise<ConcertPlace[]> =>
      check(
        await api(sessionToken()).GET('/v1/concerts/places', {
          params: { query: { q: data.q } },
        }),
        'Cities could not be searched right now.',
      ).items,
  )

/** Upcoming concerts by the artists of the user's albums. */
export const getArtistConcerts = createServerFn({ method: 'GET' }).handler(
  async (): Promise<ArtistConcerts> =>
    check(
      await api(sessionToken()).GET('/v1/concerts/artists'),
      'Your artists’ concerts could not be loaded.',
    ),
)

/** A page of concerts, or `noPlace` when there is neither a saved city nor a position. */
export type NearResult =
  { noPlace: false; page: ConcertPage } | { noPlace: true; message: string }

export const getConcertsNear = createServerFn({ method: 'POST' })
  .validator(
    z
      .object({
        latitude: z.number().min(-90).max(90).optional(),
        longitude: z.number().min(-180).max(180).optional(),
        radiusKm: z.union([z.literal(25), z.literal(50), z.literal(100)]),
        page: z.number().int().min(1).max(10),
      })
      .refine(
        (body) =>
          (body.latitude === undefined) === (body.longitude === undefined),
        { message: 'Send latitude and longitude together.' },
      ),
  )
  .handler(async ({ data }): Promise<NearResult> => {
    const result = await api(sessionToken()).POST('/v1/concerts/near', {
      body: data,
    })
    if (result.response.status === 409 && result.error?.code === 'no_place')
      return { noPlace: true, message: result.error.message }
    return {
      noPlace: false,
      page: check(result, 'Concerts could not be loaded.'),
    }
  })
