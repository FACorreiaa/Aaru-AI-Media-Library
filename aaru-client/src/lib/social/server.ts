import { createServerFn } from '@tanstack/solid-start'
import { getCookie } from '@tanstack/solid-start/server'
import { z } from 'zod'
import { api } from '../api/client'
import { MEDIA_TYPES } from '../media'
import { errorMessage } from '../api/errors'
import { SESSION_COOKIE } from '../session/cookie'
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

// SOC-002 friend invite links.

export type FriendInvite = components['schemas']['FriendInvite']
export type InvitePreview = components['schemas']['InvitePreview']
export type InviteRedemption = components['schemas']['InviteRedemption']
export type MediaRef = components['schemas']['MediaRef']

export const loadInvites = createServerFn({ method: 'GET' }).handler(
  async (): Promise<FriendInvite[]> =>
    check(
      await api(sessionToken()).GET('/v1/social/invites'),
      'Your invites could not be loaded.',
    ).items,
)

const mediaRef = z.object({
  titleId: z.string().uuid().optional(),
  type: z.enum(MEDIA_TYPES),
  ids: z.record(z.string(), z.string()).optional(),
  title: z.string().optional(),
  year: z.number().int().optional(),
})

export const createInvite = createServerFn({ method: 'POST' })
  .validator(z.object({ title: mediaRef.optional() }))
  .handler(async ({ data }): Promise<FriendInvite> =>
    check(
      await api(sessionToken()).POST('/v1/social/invites', {
        body: { title: data.title },
      }),
      'The invite was not made.',
    ),
  )

export const revokeInvite = createServerFn({ method: 'POST' })
  .validator(z.object({ code: z.string().min(1).max(32) }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE('/v1/social/invites/{code}', {
        params: { path: { code: data.code } },
      }),
      'That invite is already gone.',
    ),
  )

/** An invite link's page: what it shows, and who is looking (null when signed out). */
export type InvitePage = {
  /** Null when the code is unknown, spent, revoked, expired or blocked. */
  preview: InvitePreview | null
  viewer: { handle?: string; displayName?: string } | null
}

/**
 * Public: it sends the session only when there is one, so the server can say where the
 * viewer stands with the inviter and the page knows whether they still need a handle.
 */
export const loadInvite = createServerFn({ method: 'GET' })
  .validator(z.object({ code: z.string().min(1).max(32) }))
  .handler(async ({ data }): Promise<InvitePage> => {
    const token = getCookie(SESSION_COOKIE)
    const client = api(token)
    const [preview, me] = await Promise.all([
      client.GET('/v1/invites/{code}', {
        params: { path: { code: data.code } },
      }),
      token ? client.GET('/v1/me') : Promise.resolve(null),
    ])
    if (preview.response.status !== 404 && preview.data === undefined)
      throw new Error(
        errorMessage(preview.error, 'This invite could not be opened.'),
      )
    const viewer = me?.data
      ? { handle: me.data.handle, displayName: me.data.displayName }
      : null
    return { preview: preview.data ?? null, viewer }
  })

export const redeemInvite = createServerFn({ method: 'POST' })
  .validator(
    z.object({ code: z.string().min(1).max(32), addTitle: z.boolean() }),
  )
  .handler(async ({ data }): Promise<InviteRedemption> =>
    check(
      await api(sessionToken()).POST('/v1/social/invites/{code}/redeem', {
        params: { path: { code: data.code } },
        body: { addTitle: data.addTitle },
      }),
      'The invite could not be accepted.',
    ),
  )

// SOC-001 settings and SOC-003: friend profiles and activity.

export type FriendProfile = components['schemas']['FriendProfile']
export type FriendItem = components['schemas']['FriendItem']
export type ActivityItem = components['schemas']['ActivityItem']
export type ActivityPage = components['schemas']['ActivityPage']

export const loadActivity = createServerFn({ method: 'GET' })
  .validator(z.object({ before: z.string().datetime().optional() }))
  .handler(async ({ data }): Promise<ActivityPage> =>
    check(
      await api(sessionToken()).GET('/v1/activity', {
        params: { query: { before: data.before } },
      }),
      'Your friends’ activity could not be loaded.',
    ),
  )

/** A friend's profile by handle; null when they are not your friend (or not there at all). */
export const loadFriendProfile = createServerFn({ method: 'GET' })
  .validator(z.object({ handle: z.string().min(1).max(21) }))
  .handler(async ({ data }): Promise<{ profile: FriendProfile | null }> => ({
    profile: await friendProfile(data.handle),
  }))

async function friendProfile(handle: string): Promise<FriendProfile | null> {
  {
    const client = api(sessionToken())
    const found = await client.GET('/v1/social/users/{handle}', {
      params: { path: { handle } },
    })
    if (found.response.status === 401) sessionRejected()
    if (found.response.status === 404 || found.data?.relationship !== 'friend')
      return null
    const profile = await client.GET('/v1/social/friends/{userId}/profile', {
      params: { path: { userId: found.data.user.userId } },
    })
    if (profile.response.status === 404) return null
    return check(profile, 'This profile could not be loaded.')
  }
}

export const loadSocialSettings = createServerFn({ method: 'GET' }).handler(
  async () =>
    check(
      await api(sessionToken()).GET('/v1/me/social-settings'),
      'Your sharing setting could not be loaded.',
    ),
)

export type SocialSettings = components['schemas']['SocialSettings']

/** Saves the switches you changed; the rest keep their saved values (GAM-005 added two). */
export const saveSocialSettings = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      shareLibraryWithFriends: z.boolean().optional(),
      showAchievementsToFriends: z.boolean().optional(),
      leaderboardOptIn: z.boolean().optional(),
    }),
  )
  .handler(async ({ data }): Promise<SocialSettings> => {
    const client = api(sessionToken())
    const fallback = 'Your sharing setting was not saved.'
    // The library switch is required on the wire; read it when this change leaves it out.
    const shareLibraryWithFriends =
      data.shareLibraryWithFriends ??
      check(await client.GET('/v1/me/social-settings'), fallback)
        .shareLibraryWithFriends
    return check(
      await client.PUT('/v1/me/social-settings', {
        body: { ...data, shareLibraryWithFriends },
      }),
      fallback,
    )
  })

/** The Friends page: who you are, your friends and requests, and their last two weeks. */
export const loadFriendsPage = createServerFn({ method: 'GET' }).handler(
  async () => {
    const client = api(sessionToken())
    const [me, activity, social, recommendations, progress, board, posts] =
      await Promise.all([
        client.GET('/v1/me'),
        client.GET('/v1/activity'),
        loadSocial(),
        client.GET('/v1/me/recommendations'),
        client.GET('/v1/me/progress'),
        client.GET('/v1/social/leaderboard'),
        // BOARD-002: the Board's first Recent page. Here, in the handler, rather than a second
        // call in the route's loader: route options ship in every page's entry chunk.
        client.GET('/v1/board', { params: { query: { sort: 'recent' } } }),
      ])
    const account = check(me, 'Your account could not be loaded.')
    return {
      handle: account.handle,
      displayName: account.displayName,
      social,
      // A Board that fails to load says so in place; Lately still opens.
      posts: posts.data
        ? {
            data: {
              posts: posts.data.items,
              friendCount: social.friends.length,
              me: { id: account.userId, handle: account.handle },
            },
            problem: undefined,
          }
        : {
            data: null,
            problem: errorMessage(
              posts.error,
              'The Board could not be loaded.',
            ),
          },
      // GAM-002/005: the "You" card and "This week". Either missing just leaves its card out.
      progress: progress.data ?? null,
      board: board.data ?? null,
      activity: check(activity, 'Your friends’ activity could not be loaded.'),
      recommendations: check(
        recommendations,
        'Your recommendations could not be loaded.',
      ).items,
    }
  },
)

// SOC-007 reactions and SOC-006 recommendations.

export type RecommendationItem = components['schemas']['RecommendationItem']
export type Reaction = components['schemas']['ReactionSet']['emoji']

export const REACTIONS: Reaction[] = ['❤️', '😂', '😮', '😭', '🔥', '👏']

/** Sets your reaction on a row, or clears it with `null`. */
export const reactTo = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      id: z.string().min(1).max(100),
      emoji: z.enum(['❤️', '😂', '😮', '😭', '🔥', '👏']).nullable(),
    }),
  )
  .handler(async ({ data }) => {
    const client = api(sessionToken())
    const params = { params: { path: { id: data.id } } }
    checkEmpty(
      data.emoji
        ? await client.PUT('/v1/activity/{id}/reaction', {
            ...params,
            body: { emoji: data.emoji },
          })
        : await client.DELETE('/v1/activity/{id}/reaction', params),
      'That reaction was not saved.',
    )
  })

export const loadRecommendations = createServerFn({ method: 'GET' }).handler(
  async (): Promise<RecommendationItem[]> =>
    check(
      await api(sessionToken()).GET('/v1/me/recommendations'),
      'Your recommendations could not be loaded.',
    ).items,
)

export const recommend = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      to: z.array(z.string().uuid()).min(1).max(10),
      title: mediaRef,
      note: z.string().max(140).optional(),
    }),
  )
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST('/v1/social/recommendations', {
        body: data,
      }),
      'That recommendation was not sent.',
    ),
  )

/** Adds it to Plan to watch (`add`) or dismisses it. Either way it leaves the list. */
export const answerRecommendation = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid(), add: z.boolean() }))
  .handler(async ({ data }) => {
    const client = api(sessionToken())
    const params = { params: { path: { id: data.id } } }
    checkEmpty(
      data.add
        ? await client.POST('/v1/me/recommendations/{id}/add', params)
        : await client.DELETE('/v1/me/recommendations/{id}', params),
      'That recommendation is gone.',
    )
  })
