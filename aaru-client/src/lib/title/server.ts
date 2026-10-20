import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { LibraryEntry } from '../library/model'
import type { TitleDetail } from './model'

// APP-005 on the web: the same `/v1` routes the Apple apps call for the Title room.

const itemId = z.string().uuid()

/** The library item (with its watched episodes) and the title it points at. A title that
 * fails to load comes back as `titleError`, so the page can say so and offer a retry. */
export const getTitlePage = createServerFn({ method: 'GET' })
  .validator(z.object({ id: itemId }))
  .handler(
    async ({
      data,
    }): Promise<{
      entry: LibraryEntry
      title: TitleDetail | null
      titleError: string | null
    }> => {
      const client = api(sessionToken())
      const item = await client.GET('/v1/library/items/{id}', {
        params: { path: { id: data.id } },
      })
      if (item.response.status === 401) sessionRejected()
      if (!item.data)
        throw new Error(
          errorMessage(item.error, 'This title is not in your library.'),
        )
      const title = await client.GET('/v1/titles/{id}', {
        params: { path: { id: item.data.title.id } },
      })
      if (title.response.status === 401) sessionRejected()
      return {
        entry: item.data,
        title: title.data ?? null,
        titleError: title.data
          ? null
          : errorMessage(title.error, 'Episodes could not be loaded.'),
      }
    },
  )

export const setEpisode = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      id: itemId,
      season: z.number().int().min(0),
      episode: z.number().int().min(0),
      watched: z.boolean(),
    }),
  )
  .handler(async ({ data }): Promise<LibraryEntry> => {
    const {
      data: entry,
      error,
      response,
    } = await api(sessionToken()).PUT(
      '/v1/library/items/{id}/episodes/{season}/{episode}',
      {
        params: {
          path: { id: data.id, season: data.season, episode: data.episode },
        },
        body: { watched: data.watched },
      },
    )
    if (response.status === 401) sessionRejected()
    if (!entry) {
      throw new Error(
        errorMessage(error, `S${data.season} E${data.episode} was not saved.`),
      )
    }
    return entry
  })

export const markSeason = createServerFn({ method: 'POST' })
  .validator(z.object({ id: itemId, season: z.number().int().min(1) }))
  .handler(async ({ data }): Promise<LibraryEntry> => {
    const {
      data: entry,
      error,
      response,
    } = await api(sessionToken()).POST(
      '/v1/library/items/{id}/seasons/{season}/watched',
      { params: { path: { id: data.id, season: data.season } } },
    )
    if (response.status === 401) sessionRejected()
    if (!entry)
      throw new Error(
        errorMessage(error, `Season ${data.season} was not marked.`),
      )
    return entry
  })

export const updateItem = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      id: itemId,
      patch: z
        .object({
          status: z.enum(['wishlist', 'in_progress', 'finished', 'dropped']),
          rating: z.number().min(1).max(10),
          notes: z.string().max(10_000),
          isOwned: z.boolean(),
          bookPage: z.number().int().min(0),
          clear: z.array(z.enum(['rating', 'notes', 'bookProgress'])),
        })
        .partial(),
    }),
  )
  .handler(async ({ data }): Promise<LibraryEntry> => {
    const {
      data: entry,
      error,
      response,
    } = await api(sessionToken()).PATCH('/v1/library/items/{id}', {
      params: { path: { id: data.id } },
      body: data.patch,
    })
    if (response.status === 401) sessionRejected()
    if (!entry)
      throw new Error(errorMessage(error, 'That change was not saved.'))
    return entry
  })
