import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { ProfileStats } from './model'

// The profile's numbers (`/v1/me/profile/stats`): all time, from what the library holds now, so
// ticks without a watch date count too. Insights stays the place for dated activity.

export const getProfileStats = createServerFn({ method: 'GET' }).handler(
  async (): Promise<ProfileStats> => {
    const { data, error, response } = await api(sessionToken()).GET(
      '/v1/me/profile/stats',
    )
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'Your profile could not be loaded.'))
    return data
  },
)
