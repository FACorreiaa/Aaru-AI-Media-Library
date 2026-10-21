import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// OUT-004 on the web: changes an outside agent asked for wait here until the user decides.
// These routes take a session only; an agent can never approve its own plan.

export type AgentPlan = components['schemas']['AgentPlan']

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

const byID = z.object({ id: z.string().uuid() })

/** Plans still waiting, newest first. */
export const listPendingPlans = createServerFn({ method: 'GET' }).handler(
  async (): Promise<AgentPlan[]> =>
    check(
      await api(sessionToken()).GET('/v1/plans', {
        params: { query: { status: 'pending' } },
      }),
      'Requests from your agents could not be loaded.',
    ).items,
)

export const getPlan = createServerFn({ method: 'GET' })
  .validator(byID)
  .handler(async ({ data }): Promise<AgentPlan> =>
    check(
      await api(sessionToken()).GET('/v1/plans/{id}', {
        params: { path: { id: data.id } },
      }),
      'That request could not be loaded.',
    ),
  )

/** Applies the plan as one undoable action. A stale or expired plan answers its reason. */
export const approvePlan = createServerFn({ method: 'POST' })
  .validator(byID)
  .handler(
    async ({ data }): Promise<AgentPlan> =>
      check(
        await api(sessionToken()).POST('/v1/plans/{id}/approve', {
          params: { path: { id: data.id } },
        }),
        'That request was not applied.',
      ).plan,
  )

export const denyPlan = createServerFn({ method: 'POST' })
  .validator(byID)
  .handler(async ({ data }): Promise<AgentPlan> =>
    check(
      await api(sessionToken()).POST('/v1/plans/{id}/deny', {
        params: { path: { id: data.id } },
      }),
      'That request was not refused.',
    ),
  )
