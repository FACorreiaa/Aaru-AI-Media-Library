import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { MEDIA_TYPES } from '../media'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// APP-006 on the web: the same `/v1/lists` routes the Apple apps call.

export type ListSummary = components['schemas']['ListSummary']
export type ListDetail = components['schemas']['ListDetail']

const id = z.string().uuid()
const name = z.string().trim().min(1).max(120)
const mediaRef = z.object({
  titleId: z.string().uuid().optional(),
  type: z.enum(MEDIA_TYPES),
  ids: z.record(z.string(), z.string()).optional(),
  title: z.string().optional(),
  year: z.number().int().optional(),
})

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

export const getLists = createServerFn({ method: 'GET' }).handler(
  async (): Promise<ListSummary[]> =>
    check(
      await api(sessionToken()).GET('/v1/lists'),
      'Your lists could not be loaded.',
    ).items,
)

export const getList = createServerFn({ method: 'GET' })
  .validator(z.object({ id }))
  .handler(async ({ data }): Promise<ListDetail> =>
    check(
      await api(sessionToken()).GET('/v1/lists/{id}', {
        params: { path: { id: data.id } },
      }),
      'The list could not be loaded.',
    ),
  )

export const createList = createServerFn({ method: 'POST' })
  .validator(z.object({ name }))
  .handler(async ({ data }): Promise<ListDetail> =>
    check(
      await api(sessionToken()).POST('/v1/lists', {
        body: { name: data.name },
      }),
      'The list could not be created.',
    ),
  )

export const renameList = createServerFn({ method: 'POST' })
  .validator(z.object({ id, name }))
  .handler(async ({ data }): Promise<ListDetail> =>
    check(
      await api(sessionToken()).PATCH('/v1/lists/{id}', {
        params: { path: { id: data.id } },
        body: { name: data.name },
      }),
      'The list could not be renamed.',
    ),
  )

export const deleteList = createServerFn({ method: 'POST' })
  .validator(z.object({ id }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE('/v1/lists/{id}', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok) {
      throw new Error(
        errorMessage(result.error, 'The list could not be deleted.'),
      )
    }
  })

/** Adds a title to a list. Adding one that is already there changes nothing. */
export const addToList = createServerFn({ method: 'POST' })
  .validator(z.object({ id, mediaRef }))
  .handler(async ({ data }): Promise<ListDetail> =>
    check(
      await api(sessionToken()).POST('/v1/lists/{id}/items', {
        params: { path: { id: data.id } },
        body: { mediaRef: data.mediaRef },
      }),
      'The title could not be added to the list.',
    ),
  )

export const removeFromList = createServerFn({ method: 'POST' })
  .validator(z.object({ id, titleId: z.string().uuid() }))
  .handler(async ({ data }): Promise<ListDetail> =>
    check(
      await api(sessionToken()).DELETE('/v1/lists/{id}/items/{titleId}', {
        params: { path: { id: data.id, titleId: data.titleId } },
      }),
      'The title could not be removed.',
    ),
  )

export const reorderList = createServerFn({ method: 'POST' })
  .validator(z.object({ id, titleIds: z.array(z.string().uuid()) }))
  .handler(async ({ data }): Promise<ListDetail> =>
    check(
      await api(sessionToken()).PUT('/v1/lists/{id}/order', {
        params: { path: { id: data.id } },
        body: { titleIds: data.titleIds },
      }),
      'The new order was not saved.',
    ),
  )
