import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { sessionToken } from '../session/guard'
import { mediaRef } from './media-ref'
import { check, checkEmpty } from './responses'
import type { components } from '../api/schema'

// GRP-001…GRP-003 on the web, over the same `/v1/groups/*` and `/v1/group-invites/*` routes as
// the Apple apps. Every rule is the server's; these only carry the calls.

export type GroupSummary = components['schemas']['GroupSummary']
export type GroupDetail = components['schemas']['GroupDetail']
export type GroupMember = components['schemas']['GroupMember']
export type GroupInvite = components['schemas']['GroupInvite']
export type GroupRole = components['schemas']['GroupRole']
export type Channel = components['schemas']['Channel']
export type GroupMessage = components['schemas']['GroupMessage']
export type Me = components['schemas']['Me']

/** What the groups shell needs on first paint. */
export type GroupsState = {
  me: Me
  groups: GroupSummary[]
  invites: GroupInvite[]
}

const uuid = z.string().uuid()
const groupRef = z.object({ groupId: uuid })
const channelRef = z.object({ groupId: uuid, channelId: uuid })
const messageRef = z.object({ groupId: uuid, channelId: uuid, messageId: uuid })

/** You, your groups and the invites waiting for you, in one load. */
export const loadGroups = createServerFn({ method: 'GET' }).handler(
  async (): Promise<GroupsState> => {
    const client = api(sessionToken())
    const [me, groups, invites] = await Promise.all([
      client.GET('/v1/me'),
      client.GET('/v1/groups'),
      client.GET('/v1/me/group-invites'),
    ])
    const fallback = 'Your groups could not be loaded.'
    return {
      me: check(me, fallback),
      groups: check(groups, fallback).items,
      invites: check(invites, fallback).items,
    }
  },
)

export const listGroups = createServerFn({ method: 'GET' }).handler(
  async (): Promise<GroupSummary[]> =>
    check(
      await api(sessionToken()).GET('/v1/groups'),
      'Your groups could not be loaded.',
    ).items,
)

export const listGroupInvites = createServerFn({ method: 'GET' }).handler(
  async (): Promise<GroupInvite[]> =>
    check(
      await api(sessionToken()).GET('/v1/me/group-invites'),
      'Your invites could not be loaded.',
    ).items,
)

export const createGroup = createServerFn({ method: 'POST' })
  .validator(z.object({ name: z.string() }))
  .handler(async ({ data }): Promise<GroupDetail> =>
    check(
      await api(sessionToken()).POST('/v1/groups', { body: data }),
      'The group was not created.',
    ),
  )

export const getGroup = createServerFn({ method: 'GET' })
  .validator(groupRef)
  .handler(async ({ data }): Promise<GroupDetail> =>
    check(
      await api(sessionToken()).GET('/v1/groups/{groupId}', {
        params: { path: data },
      }),
      'That group could not be found.',
    ),
  )

/** Gone (404/403: deleted, or you are not in it) apart from "could not load" (UX-064). */
const gone = (status: number) => status === 404 || status === 403

/** A group for its page: `null` when it is gone; any other failure throws, for Try again. */
export const openGroup = createServerFn({ method: 'GET' })
  .validator(groupRef)
  .handler(async ({ data }): Promise<GroupDetail | null> => {
    const result = await api(sessionToken()).GET('/v1/groups/{groupId}', {
      params: { path: data },
    })
    if (gone(result.response.status)) return null
    return check(result, 'That group could not be loaded.')
  })

/** A channel's latest group messages: `null` when the channel is gone; other failures throw. */
export const openChannel = createServerFn({ method: 'GET' })
  .validator(
    channelRef.extend({ limit: z.number().int().min(1).max(100).optional() }),
  )
  .handler(async ({ data }): Promise<GroupMessage[] | null> => {
    const result = await api(sessionToken()).GET(
      '/v1/groups/{groupId}/channels/{channelId}/messages',
      {
        params: {
          path: { groupId: data.groupId, channelId: data.channelId },
          query: { limit: data.limit },
        },
      },
    )
    if (gone(result.response.status)) return null
    return check(result, 'This channel could not be loaded.').items
  })

export const updateGroup = createServerFn({ method: 'POST' })
  .validator(z.object({ groupId: uuid, name: z.string() }))
  .handler(async ({ data }): Promise<GroupDetail> =>
    check(
      await api(sessionToken()).PATCH('/v1/groups/{groupId}', {
        params: { path: { groupId: data.groupId } },
        body: { name: data.name },
      }),
      'The group was not renamed.',
    ),
  )

/** Mutes or unmutes this group's mention alerts for me (GRP-012). Nobody else sees it. */
export const setGroupMuted = createServerFn({ method: 'POST' })
  .validator(z.object({ groupId: uuid, muted: z.boolean() }))
  .handler(async ({ data }): Promise<GroupSummary> =>
    check(
      await api(sessionToken()).PUT('/v1/groups/{groupId}/me', {
        params: { path: { groupId: data.groupId } },
        body: { muted: data.muted },
      }),
      'That setting was not saved.',
    ),
  )

export const deleteGroup = createServerFn({ method: 'POST' })
  .validator(groupRef)
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE('/v1/groups/{groupId}', {
        params: { path: data },
      }),
      'The group was not deleted.',
    ),
  )

export const updateGroupMember = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      groupId: uuid,
      userId: uuid,
      role: z.enum(['admin', 'member']),
    }),
  )
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).PATCH('/v1/groups/{groupId}/members/{userId}', {
        params: { path: { groupId: data.groupId, userId: data.userId } },
        body: { role: data.role },
      }),
      'That role was not changed.',
    ),
  )

/** Removes a member, or yourself to leave. */
export const removeGroupMember = createServerFn({ method: 'POST' })
  .validator(z.object({ groupId: uuid, userId: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE(
        '/v1/groups/{groupId}/members/{userId}',
        { params: { path: data } },
      ),
      'That member was not removed.',
    ),
  )

export const transferGroup = createServerFn({ method: 'POST' })
  .validator(z.object({ groupId: uuid, userId: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST('/v1/groups/{groupId}/transfer', {
        params: { path: { groupId: data.groupId } },
        body: { userId: data.userId },
      }),
      'Ownership was not transferred.',
    ),
  )

export const inviteToGroup = createServerFn({ method: 'POST' })
  .validator(z.object({ groupId: uuid, userId: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST('/v1/groups/{groupId}/invites', {
        params: { path: { groupId: data.groupId } },
        body: { userId: data.userId },
      }),
      'That invite was not sent.',
    ),
  )

export const acceptGroupInvite = createServerFn({ method: 'POST' })
  .validator(z.object({ id: uuid }))
  .handler(async ({ data }): Promise<GroupSummary> =>
    check(
      await api(sessionToken()).POST('/v1/group-invites/{id}/accept', {
        params: { path: data },
      }),
      'That invite could not be accepted.',
    ),
  )

/** Declines an invite to you, or cancels one you sent. */
export const declineGroupInvite = createServerFn({ method: 'POST' })
  .validator(z.object({ id: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE('/v1/group-invites/{id}', {
        params: { path: data },
      }),
      'That invite is already gone.',
    ),
  )

/** Makes a channel. A title channel takes the title, and its name when none is given. */
export const createChannel = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      groupId: uuid,
      kind: z.enum(['text', 'title', 'watch', 'shelf']).optional(),
      name: z.string().optional(),
      topic: z.string().optional(),
      title: mediaRef.optional(),
    }),
  )
  .handler(async ({ data }): Promise<Channel> =>
    check(
      await api(sessionToken()).POST('/v1/groups/{groupId}/channels', {
        params: { path: { groupId: data.groupId } },
        body: {
          kind: data.kind,
          name: data.name,
          topic: data.topic,
          title: data.title,
        },
      }),
      'The channel was not created.',
    ),
  )

export const updateChannel = createServerFn({ method: 'POST' })
  .validator(
    channelRef.extend({
      name: z.string().optional(),
      topic: z.string().optional(),
    }),
  )
  .handler(async ({ data }): Promise<Channel> =>
    check(
      await api(sessionToken()).PATCH(
        '/v1/groups/{groupId}/channels/{channelId}',
        {
          params: {
            path: { groupId: data.groupId, channelId: data.channelId },
          },
          body: { name: data.name, topic: data.topic },
        },
      ),
      'The channel was not saved.',
    ),
  )

export const deleteChannel = createServerFn({ method: 'POST' })
  .validator(channelRef)
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE(
        '/v1/groups/{groupId}/channels/{channelId}',
        { params: { path: data } },
      ),
      'The channel was not deleted.',
    ),
  )

export const listMessages = createServerFn({ method: 'GET' })
  .validator(
    channelRef.extend({
      before: uuid.optional(),
      after: uuid.optional(),
      limit: z.number().int().min(1).max(100).optional(),
    }),
  )
  .handler(
    async ({ data }): Promise<GroupMessage[]> =>
      check(
        await api(sessionToken()).GET(
          '/v1/groups/{groupId}/channels/{channelId}/messages',
          {
            params: {
              path: { groupId: data.groupId, channelId: data.channelId },
              query: {
                before: data.before,
                after: data.after,
                limit: data.limit,
              },
            },
          },
        ),
        'Group messages could not be loaded.',
      ).items,
  )

export const postMessage = createServerFn({ method: 'POST' })
  .validator(
    channelRef.extend({
      body: z.string(),
      clientNonce: z.string().max(64),
      // Title channels (GRP-007): a hand stamp, or none at all. Absent: my progress.
      spoiler: z
        .object({
          season: z.number().int().optional(),
          episode: z.number().int().optional(),
          ending: z.boolean().optional(),
        })
        .optional(),
      spoilerFree: z.boolean().optional(),
    }),
  )
  .handler(async ({ data }): Promise<GroupMessage> =>
    check(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/messages',
        {
          params: {
            path: { groupId: data.groupId, channelId: data.channelId },
          },
          body: {
            body: data.body,
            clientNonce: data.clientNonce,
            spoiler: data.spoiler,
            spoilerFree: data.spoilerFree,
          },
        },
      ),
      'That was not sent.',
    ),
  )

export const editMessage = createServerFn({ method: 'POST' })
  .validator(messageRef.extend({ body: z.string() }))
  .handler(async ({ data }): Promise<GroupMessage> =>
    check(
      await api(sessionToken()).PATCH(
        '/v1/groups/{groupId}/channels/{channelId}/messages/{messageId}',
        {
          params: {
            path: {
              groupId: data.groupId,
              channelId: data.channelId,
              messageId: data.messageId,
            },
          },
          body: { body: data.body },
        },
      ),
      'That change was not saved.',
    ),
  )

export const deleteMessage = createServerFn({ method: 'POST' })
  .validator(messageRef)
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE(
        '/v1/groups/{groupId}/channels/{channelId}/messages/{messageId}',
        { params: { path: data } },
      ),
      'That was not deleted.',
    ),
  )

export const markChannelRead = createServerFn({ method: 'POST' })
  .validator(channelRef.extend({ messageId: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/read',
        {
          params: {
            path: { groupId: data.groupId, channelId: data.channelId },
          },
          body: { messageId: data.messageId },
        },
      ),
      'The channel was not marked read.',
    ),
  )
