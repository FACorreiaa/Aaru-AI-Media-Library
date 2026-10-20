import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'

// GRP-006 on the web. The session token never reaches the browser (HttpOnly cookie), and a
// browser WebSocket cannot send an Authorization header, so the Worker trades the session for a
// single-use ticket the browser opens the socket with.

export type RealtimeTicket = { url: string; expiresAt: string }

export const realtimeTicket = createServerFn({ method: 'POST' }).handler(
  async (): Promise<RealtimeTicket> => {
    const result = await api(sessionToken()).POST('/v1/realtime/ticket')
    if (result.response.status === 401) sessionRejected()
    if (!result.data)
      throw new Error(errorMessage(result.error, 'Live updates are off.'))
    return { url: result.data.url, expiresAt: result.data.expiresAt }
  },
)
