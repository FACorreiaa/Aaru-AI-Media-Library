import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// SOC-001 / SOC-002 on the web, over the same `/v1/me/profile` and `/v1/social/*` routes as
// the Apple apps.

export type SocialUser = components['schemas']['SocialUser']
export type SocialUserView = components['schemas']['SocialUserView']
export type FriendRequest = components['schemas']['FriendRequest']

export type SocialState = {
  friends: SocialUser[]
  incoming: FriendRequest[]
  outgoing: FriendRequest[]
  blocked: SocialUser[]
}

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

function checkEmpty(
  result: { error?: unknown; response: Response },
  fallback: string,
) {
  if (result.response.status === 401) sessionRejected()
  if (!result.response.ok) throw new Error(errorMessage(result.error, fallback))
}

/** Friends, requests both ways, and blocks, in one load. */
export const loadSocial = createServerFn({ method: 'GET' }).handler(
  async (): Promise<SocialState> => {
    const client = api(sessionToken())
    const [friends, requests, blocked] = await Promise.all([
      client.GET('/v1/social/friends'),
      client.GET('/v1/social/friend-requests'),
      client.GET('/v1/social/blocks'),
    ])
    const fallback = 'Your friends could not be loaded.'
    const both = check(requests, fallback)
    return {
      friends: check(friends, fallback).items,
      incoming: both.incoming,
      outgoing: both.outgoing,
      blocked: check(blocked, fallback).items,
    }
  },
)

export const saveProfile = createServerFn({ method: 'POST' })
  .validator(
    z.object({ handle: z.string(), displayName: z.string().optional() }),
  )
  .handler(async ({ data }): Promise<SocialUser> =>
    check(
      await api(sessionToken()).PUT('/v1/me/profile', { body: data }),
      'Your handle was not saved.',
    ),
  )

export const sendFriendRequest = createServerFn({ method: 'POST' })
  .validator(z.object({ handle: z.string() }))
  .handler(async ({ data }): Promise<SocialUserView> =>
    check(
      await api(sessionToken()).POST('/v1/social/friend-requests', {
        body: data,
      }),
      'That request was not sent.',
    ),
  )

export const acceptFriendRequest = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }): Promise<SocialUser> =>
    check(
      await api(sessionToken()).POST('/v1/social/friend-requests/{id}/accept', {
        params: { path: { id: data.id } },
      }),
      'That request could not be accepted.',
    ),
  )

/** Declines a request to you, or cancels one you sent. */
export const withdrawFriendRequest = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE('/v1/social/friend-requests/{id}', {
        params: { path: { id: data.id } },
      }),
      'That request is already gone.',
    ),
  )

export const removeFriend = createServerFn({ method: 'POST' })
  .validator(z.object({ userId: z.string().uuid() }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE('/v1/social/friends/{userId}', {
        params: { path: { userId: data.userId } },
      }),
      'That friend was not removed.',
    ),
  )

export const blockUser = createServerFn({ method: 'POST' })
  .validator(z.object({ userId: z.string().uuid() }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).PUT('/v1/social/blocks/{userId}', {
        params: { path: { userId: data.userId } },
      }),
      'That person was not blocked.',
    ),
  )

export const unblockUser = createServerFn({ method: 'POST' })
  .validator(z.object({ userId: z.string().uuid() }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE('/v1/social/blocks/{userId}', {
        params: { path: { userId: data.userId } },
      }),
      'That person was not unblocked.',
    ),
  )
