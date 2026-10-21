import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// Alerts on the web: the account's switches (new episodes, group mentions and invites, shared
// with the Apple apps) and this browser's push subscription, over `/v1/me/notifications` and
// `/v1/web-push/*`.

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

export type NotificationSettings = components['schemas']['NotificationSettings']

export type PushSetup = {
  settings: NotificationSettings
  /** The VAPID key browsers subscribe with; null when the server has no web push. */
  publicKey: string | null
}

export const getPushSetup = createServerFn({ method: 'GET' }).handler(
  async (): Promise<PushSetup> => {
    const client = api(sessionToken())
    const [settings, key] = await Promise.all([
      client.GET('/v1/me/notifications'),
      client.GET('/v1/web-push/key'),
    ])
    const loaded = check(
      settings,
      'Your notification settings could not be loaded.',
    )
    if (key.response.status === 401) sessionRejected()
    return { settings: loaded, publicKey: key.data?.publicKey ?? null }
  },
)

/** Changes the switches sent; the others keep their value. */
export const saveNotifications = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      airing: z.boolean().optional(),
      groupMentions: z.boolean().optional(),
      groupInvites: z.boolean().optional(),
    }),
  )
  .handler(async ({ data }): Promise<NotificationSettings> =>
    check(
      await api(sessionToken()).PUT('/v1/me/notifications', { body: data }),
      'That was not saved.',
    ),
  )

const subscription = z.object({
  endpoint: z.string().url().max(2048),
  keys: z.object({ p256dh: z.string().max(200), auth: z.string().max(200) }),
})

export const saveSubscription = createServerFn({ method: 'POST' })
  .validator(subscription)
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).PUT('/v1/web-push/subscriptions', {
      body: data,
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok)
      throw new Error(
        errorMessage(result.error, 'This browser could not be signed up.'),
      )
  })

export const deleteSubscription = createServerFn({ method: 'POST' })
  .validator(z.object({ endpoint: z.string().url().max(2048) }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE(
      '/v1/web-push/subscriptions',
      { params: { query: { endpoint: data.endpoint } } },
    )
    if (result.response.status === 401) sessionRejected()
  })
