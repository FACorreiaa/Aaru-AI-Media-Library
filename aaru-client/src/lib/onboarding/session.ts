import type { QueryClient } from '@tanstack/solid-query'
import { SESSION_KEY } from '../session/query'
import type { Session } from '../session/session'

// Apart from `session/query.ts`, which the shell's `beforeLoad` puts in every page's first load:
// only the first run calls this.

/** The first run ended (finished or skipped): this tab stops sending you to it, and pages read
 * before it (none, usually) are asked again, since the flow added to the library. */
export function onboardingFinished(queryClient: QueryClient) {
  queryClient.setQueryData<Session>(SESSION_KEY, (session) =>
    session?.signedIn ? { ...session, onboardingPending: false } : session,
  )
  queryClient.removeQueries({
    predicate: (query) => query.queryKey[0] !== SESSION_KEY[0],
  })
}
