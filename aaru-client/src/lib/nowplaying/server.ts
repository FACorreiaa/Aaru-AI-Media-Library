import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { NowPlaying } from './model'

// SCR-008 on the web: `/v1/me/now-playing`, asked again every half minute while Home is in
// view. Null when nothing plays.

export const getNowPlaying = createServerFn({ method: 'GET' }).handler(
  async (): Promise<NowPlaying | null> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/me/now-playing')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(
        errorMessage(error, 'What is playing could not be loaded.'),
      )
    return data.nowPlaying ?? null
  },
)
