import { queryOptions } from '@tanstack/solid-query'
import type { QueryClient } from '@tanstack/solid-query'
import { redirect } from '@tanstack/solid-router'
import { getSession } from './session'
import type { Session } from './session'

// The signed-in check for app pages, once per tab instead of once per navigation and hover.
// It is only a gate: every server function still sends the cookie, and a 401 from any of
// them clears it and goes to sign-in (`guard.ts`).

export const SESSION_KEY = ['session'] as const

const sessionQuery = queryOptions({
  queryKey: SESSION_KEY,
  queryFn: () => getSession(),
  staleTime: Infinity,
})

/** The signed-in session for a `beforeLoad`, or a redirect to sign-in that carries `next`
 * (UX-011), so a push or an email link lands where it pointed once you are in. A signed-out
 * answer is never kept, so signing in is seen on the next navigation. */
export async function requireSession(
  queryClient: QueryClient,
  next?: string,
): Promise<Extract<Session, { signedIn: true }>> {
  const session = await queryClient.query(sessionQuery)
  if (!session.signedIn) {
    queryClient.removeQueries({ queryKey: SESSION_KEY })
    throw redirect({ to: '/sign-in', search: next ? { next } : {} })
  }
  return session
}

/** The session changed under this tab (a new name or handle): ask again on the next read. */
export function forgetSession(queryClient: QueryClient) {
  queryClient.removeQueries({ queryKey: SESSION_KEY })
}

/** Signing out, or landing on sign-in signed out: nothing of the last account stays in
 * this tab. */
export function forgetAccount(queryClient: QueryClient) {
  queryClient.clear()
}
