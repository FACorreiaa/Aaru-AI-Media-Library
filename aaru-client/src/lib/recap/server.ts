import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { Stats } from './model'

// GAM-006a on the web: `/v1/me/stats` for one year or month. The browser sends its own time
// zone; the Worker runs in UTC and must not decide where the viewer's days begin.

export const getStats = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      year: z.number().int().min(1900).max(2200),
      month: z.number().int().min(1).max(12).optional(),
      tz: z.string().min(1).max(64),
    }),
  )
  .handler(async ({ data }): Promise<Stats> => {
    const {
      data: stats,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/me/stats', {
      params: { query: { year: data.year, month: data.month, tz: data.tz } },
    })
    if (response.status === 401) sessionRejected()
    if (!stats)
      throw new Error(errorMessage(error, 'Your recap could not be loaded.'))
    return stats
  })
