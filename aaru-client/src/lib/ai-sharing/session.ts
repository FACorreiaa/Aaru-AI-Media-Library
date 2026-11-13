import type { QueryClient } from '@tanstack/solid-query'
import { SESSION_KEY } from '../session/query'
import type { Session } from '../session/session'
import type { AiSharingState } from './model'

/** The user answered (PRV-002): this tab's session says so, so nothing asks again. */
export function aiSharingAnswered(
  queryClient: QueryClient | undefined,
  state: AiSharingState,
) {
  queryClient?.setQueryData<Session>(SESSION_KEY, (session) =>
    session?.signedIn ? { ...session, aiSharing: state } : session,
  )
}
