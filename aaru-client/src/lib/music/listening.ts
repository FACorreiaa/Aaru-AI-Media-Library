import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// MUS-008 on the web: the listening log and its top lists, over the same `/v1/me/listens`
// routes as the Apple apps. Periods are read like `/v1/me/stats`, in the browser's time zone.

export type Listen = components['schemas']['Listen']
export type ListenPage = components['schemas']['ListenPage']
export type ListenTop = components['schemas']['ListenTop']
export type TopRow = ListenTop['items'][number]

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** A page of listens, newest first; pass the last page's `next` as `before`. */
export const listListens = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      before: z.string().datetime({ offset: true }).optional(),
      limit: z.number().int().min(1).max(100).optional(),
    }),
  )
  .handler(async ({ data }): Promise<ListenPage> =>
    check(
      await api(sessionToken()).GET('/v1/me/listens', {
        params: { query: { before: data.before, limit: data.limit } },
      }),
      'Your listens could not be loaded.',
    ),
  )

export const topListens = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      by: z.enum(['artist', 'track', 'album']),
      year: z.number().int().min(1900).max(2200).optional(),
      month: z.number().int().min(1).max(12).optional(),
      span: z.enum(['all', 'last7', 'last30']).optional(),
      tz: z.string().min(1).max(64),
      limit: z.number().int().min(1).max(50).optional(),
    }),
  )
  .handler(async ({ data }): Promise<ListenTop> =>
    check(
      await api(sessionToken()).GET('/v1/me/listens/top', {
        params: { query: data },
      }),
      'Your top list could not be loaded.',
    ),
  )
