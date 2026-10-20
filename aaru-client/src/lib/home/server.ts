import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
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
