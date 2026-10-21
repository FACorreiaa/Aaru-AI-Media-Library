import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { Stats } from './model'

// GAM-006a on the web: `/v1/me/stats` for one year, one month, all time (`span: 'all'`), or
// the last 7 or 30 days (`span: 'last7' | 'last30'`); a span takes no year or month. The browser sends its own time zone; the Worker runs in UTC and must not
// decide where the viewer's days begin.

export const getStats = createServerFn({ method: 'GET' })
  .validator(
    z
      .object({
        year: z.number().int().min(1900).max(2200).optional(),
        month: z.number().int().min(1).max(12).optional(),
        span: z.enum(['all', 'last7', 'last30']).optional(),
        tz: z.string().min(1).max(64),
      })
      .refine(
        (q) =>
          q.span
            ? q.year === undefined && q.month === undefined
            : q.year !== undefined,
        { message: 'Ask for a year, a month, all time, or recent days.' },
      ),
  )
  .handler(async ({ data }): Promise<Stats> => {
    const {
      data: stats,
      error,
      response,
    } = await api(sessionToken()).GET('/v1/me/stats', {
      params: {
        query: {
          year: data.year,
          month: data.month,
          span: data.span,
          tz: data.tz,
        },
      },
    })
    if (response.status === 401) sessionRejected()
    if (!stats)
      throw new Error(errorMessage(error, 'Your stats could not be loaded.'))
    return stats
  })
