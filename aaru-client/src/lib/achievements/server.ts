import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { Badge, Leaderboard, PointsPage, Progress } from './model'

// GAM-001…005 on the web, over the same `/v1/me/progress`, `/v1/me/badges`, `/v1/me/points`
// and `/v1/social/leaderboard` routes as the Apple apps. Every call carries the viewer's zone
// (`api()`), so "today" and "this week" are theirs.

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** Level, points, the streak, and badges not yet shown. */
export const getProgress = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Progress> =>
    check(
      await api(sessionToken()).GET('/v1/me/progress'),
      'Your progress could not be loaded.',
    ),
)

/** The whole catalog with your progress; hidden ones not earned carry no copy. */
export const getBadges = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Badge[]> =>
    check(
      await api(sessionToken()).GET('/v1/me/badges'),
      'Your badges could not be loaded.',
    ).items,
)

export const markBadgesSeen = createServerFn({ method: 'POST' })
  .validator(z.object({ ids: z.array(z.string().uuid()).min(1).max(200) }))
  .handler(async ({ data }) => {
    const { error, response } = await api(sessionToken()).POST(
      '/v1/me/badges/seen',
      { body: data },
    )
    if (response.status === 401) sessionRejected()
    if (!response.ok)
      throw new Error(errorMessage(error, 'Your badges were not updated.'))
  })

/** "How you earned it": the points ledger, newest first, a page at a time. */
export const getPoints = createServerFn({ method: 'GET' })
  .validator(z.object({ before: z.string().datetime().optional() }))
  .handler(async ({ data }): Promise<PointsPage> =>
    check(
      await api(sessionToken()).GET('/v1/me/points', {
        params: { query: { before: data.before, limit: 50 } },
      }),
      'Your points could not be loaded.',
    ),
  )

/** This week's friends board (or an ISO week, `2026-W43`). Empty until you join. */
export const getLeaderboard = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      week: z
        .string()
        .regex(/^\d{4}-W\d{2}$/)
        .optional(),
    }),
  )
  .handler(async ({ data }): Promise<Leaderboard> =>
    check(
      await api(sessionToken()).GET('/v1/social/leaderboard', {
        params: { query: { week: data.week } },
      }),
      'The board could not be loaded.',
    ),
  )
