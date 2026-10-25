import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { SportSettings } from './model'

// The one Sports read that loaders make (the Sports page, Settings), on its own: loaders ship
// with every page, and the rest of `./server` belongs to the Sports page alone.

/** Whether Sports are on, and the "Where to watch" country. */
export const getSportSettings = createServerFn({ method: 'GET' }).handler(
  async (): Promise<SportSettings> => {
    const result = await api(sessionToken()).GET('/v1/me/sport-settings')
    if (result.response.status === 401) sessionRejected()
    if (result.data === undefined)
      throw new Error(
        errorMessage(result.error, 'Sports settings could not be loaded.'),
      )
    return result.data
  },
)
