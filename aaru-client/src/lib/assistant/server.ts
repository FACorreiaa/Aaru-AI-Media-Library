import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// ASK-009 on the web: what the assistant needs besides its two streaming routes.

export type ChatStatus = components['schemas']['ChatStatus']

/** Whether Aaru and voice are on; the owl and the mic hide when the server has them off. */
export const getAssistantStatus = createServerFn({ method: 'GET' }).handler(
  async (): Promise<ChatStatus> => {
    const result = await api(sessionToken()).GET('/v1/chats/status')
    if (result.response.status === 401) sessionRejected()
    return result.data ?? { assistant: false, voice: false }
  },
)

/** A new chat, for the first question or after 15 minutes away. */
export const createChat = createServerFn({ method: 'POST' }).handler(
  async (): Promise<string> => {
    const result = await api(sessionToken()).POST('/v1/chats')
    if (result.response.status === 401) sessionRejected()
    if (!result.data)
      throw new Error(
        errorMessage(result.error, 'Aaru could not start a chat.'),
      )
    return result.data.id
  },
)

/** Settings → Your data → Delete my chats with Aaru. */
export const deleteChats = createServerFn({ method: 'POST' }).handler(
  async (): Promise<void> => {
    const result = await api(sessionToken()).DELETE('/v1/chats')
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok)
      throw new Error(
        errorMessage(result.error, 'Your chats were not deleted.'),
      )
  },
)
