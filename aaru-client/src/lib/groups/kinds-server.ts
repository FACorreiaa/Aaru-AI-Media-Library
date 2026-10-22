import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { MEDIA_TYPES } from '../media'
import { api } from '../api/client'
import { sessionToken } from '../session/guard'
import type { components } from '../api/schema'
import type { LibraryEntry } from '../library/model'
import { check, checkEmpty } from './responses'
import type { GroupSummary } from './server'

// GRP-007…GRP-009 on the web: the calls behind title, shelf and watch channels. Every rule is
// the server's; "Add to my library" and "Mark watched for me" are the viewer's own taps.

export type ChannelProgress = components['schemas']['ChannelProgress']
export type ChannelItem = components['schemas']['ChannelItem']
export type WatchPartyView = components['schemas']['WatchPartyView']

const uuid = z.string().uuid()
// The server's `MediaRef`, as in ./server. Private for the same reason: no zod in the browser.
const mediaRef = z.object({
  titleId: uuid.optional(),
  type: z.enum(MEDIA_TYPES),
  ids: z.record(z.string(), z.string()).optional(),
  title: z.string().optional(),
  year: z.number().int().optional(),
})
const channelRef = z.object({ groupId: uuid, channelId: uuid })
const path = (data: { groupId: string; channelId: string }) => ({
  params: { path: { groupId: data.groupId, channelId: data.channelId } },
})

/** Shows or hides my progress in this group's title channels. */
export const setShareProgress = createServerFn({ method: 'POST' })
  .validator(z.object({ groupId: uuid, shareProgress: z.boolean() }))
  .handler(async ({ data }): Promise<GroupSummary> =>
    check(
      await api(sessionToken()).PUT('/v1/groups/{groupId}/me', {
        params: { path: { groupId: data.groupId } },
        body: { shareProgress: data.shareProgress },
      }),
      'That setting was not saved.',
    ),
  )

export const getChannelProgress = createServerFn({ method: 'GET' })
  .validator(channelRef)
  .handler(async ({ data }): Promise<ChannelProgress> =>
    check(
      await api(sessionToken()).GET(
        '/v1/groups/{groupId}/channels/{channelId}/progress',
        path(data),
      ),
      'Progress could not be loaded.',
    ),
  )

// MARK: Shelf

export const listChannelItems = createServerFn({ method: 'GET' })
  .validator(channelRef)
  .handler(
    async ({ data }): Promise<ChannelItem[]> =>
      check(
        await api(sessionToken()).GET(
          '/v1/groups/{groupId}/channels/{channelId}/items',
          path(data),
        ),
        'The list could not be loaded.',
      ).items,
  )

export const addChannelItem = createServerFn({ method: 'POST' })
  .validator(channelRef.extend({ title: mediaRef }))
  .handler(
    async ({ data }): Promise<ChannelItem[]> =>
      check(
        await api(sessionToken()).POST(
          '/v1/groups/{groupId}/channels/{channelId}/items',
          { ...path(data), body: { title: data.title } },
        ),
        'That title was not added.',
      ).items,
  )

export const removeChannelItem = createServerFn({ method: 'POST' })
  .validator(channelRef.extend({ titleId: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE(
        '/v1/groups/{groupId}/channels/{channelId}/items/{titleId}',
        { params: { path: data } },
      ),
      'That title was not removed.',
    ),
  )

/** "Add to my library" from a List channel: the same journaled add as anywhere else. */
export const addTitleToLibrary = createServerFn({ method: 'POST' })
  .validator(z.object({ titleId: uuid, type: z.enum(MEDIA_TYPES) }))
  .handler(async ({ data }): Promise<LibraryEntry> =>
    check(
      await api(sessionToken()).POST('/v1/library/items', {
        body: { mediaRef: { titleId: data.titleId, type: data.type } },
      }),
      'That title was not added to your library.',
    ),
  )

// MARK: Watch parties

export const getWatchParty = createServerFn({ method: 'GET' })
  .validator(channelRef)
  .handler(async ({ data }): Promise<WatchPartyView> =>
    check(
      await api(sessionToken()).GET(
        '/v1/groups/{groupId}/channels/{channelId}/party',
        path(data),
      ),
      'The watch party could not be loaded.',
    ),
  )

export const openWatchParty = createServerFn({ method: 'POST' })
  .validator(
    channelRef.extend({
      title: mediaRef,
      season: z.number().int().optional(),
      episode: z.number().int().optional(),
    }),
  )
  .handler(async ({ data }): Promise<WatchPartyView> =>
    check(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/party',
        {
          ...path(data),
          body: {
            title: data.title,
            season: data.season,
            episode: data.episode,
          },
        },
      ),
      'The watch party was not started.',
    ),
  )

export const setWatchPartyReady = createServerFn({ method: 'POST' })
  .validator(channelRef.extend({ ready: z.boolean() }))
  .handler(async ({ data }): Promise<WatchPartyView> =>
    check(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/party/ready',
        { ...path(data), body: { ready: data.ready } },
      ),
      'That was not saved.',
    ),
  )

export const startWatchParty = createServerFn({ method: 'POST' })
  .validator(
    channelRef.extend({ countdownSeconds: z.number().int().optional() }),
  )
  .handler(async ({ data }): Promise<WatchPartyView> =>
    check(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/party/start',
        { ...path(data), body: { countdownSeconds: data.countdownSeconds } },
      ),
      'The countdown did not start.',
    ),
  )

export const endWatchParty = createServerFn({ method: 'POST' })
  .validator(channelRef)
  .handler(async ({ data }): Promise<WatchPartyView> =>
    check(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/party/end',
        path(data),
      ),
      'The party did not end.',
    ),
  )

/** Ticks the party's episode, film or book in my own library. Nobody else's. */
export const markWatchPartyWatched = createServerFn({ method: 'POST' })
  .validator(channelRef)
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST(
        '/v1/groups/{groupId}/channels/{channelId}/party/watched',
        path(data),
      ),
      'That was not marked watched.',
    ),
  )
