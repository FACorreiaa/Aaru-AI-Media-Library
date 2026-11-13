import { Outlet, createFileRoute } from '@tanstack/solid-router'
import { AppShell } from '../components/shell/AppShell'
import {
  requireAiSharingAnswered,
  requireOnboarded,
  requireSession,
} from '../lib/session/query'
import { readSidebarOpen } from '../lib/sidebar-read'

// The one layout every signed-in `/app` page renders in (DESIGN.md §18, UX-002). It also holds
// the one sign-in check: a signed-out visit goes to sign-in with `next`, so a link from a push or
// an email lands where it pointed once you are in (UX-011). A new account's first run comes
// before any of it (ONB-001), with the same `next`; then, for an account that never answered it,
// the AI sharing question (PRV-002).
export const Route = createFileRoute('/_shell')({
  // Asked once per tab through the query cache, not on every navigation.
  beforeLoad: async ({ location, context }) => {
    const session = await requireSession(context.queryClient, location.href)
    requireOnboarded(session, location.href)
    requireAiSharingAnswered(session, location.href)
    return { session }
  },
  loader: ({ context }) => ({
    session: {
      displayName: context.session.displayName,
      handle: context.session.handle,
      avatarUrl: context.session.avatarUrl ?? null,
      aiSharing: context.session.aiSharing,
    },
    sidebarOpen: readSidebarOpen(),
  }),
  component: ShellLayout,
})

function ShellLayout() {
  const loaded = Route.useLoaderData()
  return (
    <AppShell session={loaded().session} defaultOpen={loaded().sidebarOpen}>
      <Outlet />
    </AppShell>
  )
}
