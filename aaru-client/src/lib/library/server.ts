import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { MEDIA_TYPES } from '../media'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import { SEARCH_TYPES } from './model'
import type { LibraryEntry, SearchResults } from './model'

// APP-003/APP-004 on the web: the same `/v1` routes the Apple apps call, sent with the session.

/** The whole library, as the Apple apps' first sync gets it. */
export const getLibrary = createServerFn({ method: 'GET' }).handler(
  async (): Promise<LibraryEntry[]> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/library/sync')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'The library could not be loaded.'))
    return data.items
  },
)

export const searchCatalog = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      q: z.string().trim().min(2).max(200),
      type: z.enum(SEARCH_TYPES),
    }),
  )
  /** `incomplete` is true when a catalog did not answer: the hits are what the others found. */
  .handler(async ({ data }): Promise<SearchResults> => {
    const {
      data: results,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/search', {
      params: { query: { q: data.q, type: data.type } },
    })
    if (response.status === 401) sessionRejected()
    if (!results)
      throw new Error(errorMessage(error, 'Search is not available right now.'))
    return { items: results.items, incomplete: results.incomplete }
  })

const externalIds = z
  .object({
    tmdb: z.string(),
    imdb: z.string(),
    trakt: z.string(),
    tvdb: z.string(),
    isbn: z.string(),
    openLibrary: z.string(),
    anilist: z.string(),
    mal: z.string(),
    anidb: z.string(),
    musicbrainz: z.string(),
  })
  .partial()

export const addToLibrary = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      type: z.enum(MEDIA_TYPES),
      ids: externalIds,
      title: z.string(),
      year: z.number().int().optional(),
      status: z.enum(['wishlist', 'in_progress', 'finished', 'dropped']),
    }),
  )
  .handler(async ({ data }): Promise<LibraryEntry> => {
    const {
      data: entry,
      error,
      response,
    } = await api(sessionToken()).POST('/v1/library/items', {
      body: {
        mediaRef: {
          type: data.type,
          ids: data.ids,
          title: data.title,
          year: data.year,
        },
        status: data.status,
      },
    })
    if (response.status === 401) sessionRejected()
    if (!entry)
      throw new Error(errorMessage(error, `${data.title} could not be added.`))
    return entry
  })
