import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { Action } from './model'

// Settings → Your data → History: the action journal (`/v1/actions`, newest first) and its
// per-action undo, which the server journals as its own action (409 when already undone).

export const listActions = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Action[]> => {
    const { data, error, response } = await api(sessionToken()).GET(
      '/v1/actions',
      { params: { query: { limit: 100 } } },
    )
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'Your history could not be loaded.'))
    return data.items
  },
)

export const undoAction = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }): Promise<Action> => {
    const {
      data: undo,
      error,
      response,
    } = await api(sessionToken()).POST('/v1/actions/{id}/undo', {
      params: { path: { id: data.id } },
    })
    if (response.status === 401) sessionRejected()
    if (response.status === 409) throw new Error('That was already undone.')
    if (!undo) throw new Error(errorMessage(error, 'That could not be undone.'))
    return undo
  })
