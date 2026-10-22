import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import { playingItems } from './model'
import type { NowPlayingItem } from './model'

// SCR-008 and SCR-009 on the web: `/v1/me/now-playing`, asked again every half minute while
// Home is in view. Everything playing, in the server's order; empty when nothing plays.

export const getNowPlaying = createServerFn({ method: 'GET' }).handler(
  async (): Promise<NowPlayingItem[]> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/me/now-playing')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(
        errorMessage(error, 'What is playing could not be loaded.'),
      )
    return playingItems(data)
  },
)
