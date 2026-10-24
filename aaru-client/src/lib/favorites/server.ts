import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { mediaRef } from '../groups/media-ref'
import { sessionRejected, sessionToken } from '../session/guard'
import { FAVORITE_KINDS, FAVORITE_LIMIT } from './model'
import type { Favorites } from './model'

// FAV-001 on the web, over `/v1/me/favorites` like the Apple apps.

export const loadFavorites = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Favorites> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/me/favorites')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(
        errorMessage(error, 'Your favorites could not be loaded.'),
      )
    return data
  },
)

/** Replaces one kind, in order: adding, removing and moving are all this one call. */
export const saveFavorites = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      kind: z.enum(FAVORITE_KINDS),
      items: z.array(mediaRef).max(FAVORITE_LIMIT),
    }),
  )
  .handler(async ({ data }): Promise<Favorites> => {
    const {
      data: saved,
      error,
      response,
    } = await api(sessionToken()).PUT('/v1/me/favorites/{kind}', {
      params: { path: { kind: data.kind } },
      body: { items: data.items },
    })
    if (response.status === 401) sessionRejected()
    if (!saved)
      throw new Error(errorMessage(error, 'Your favorites were not saved.'))
    return saved
  })
