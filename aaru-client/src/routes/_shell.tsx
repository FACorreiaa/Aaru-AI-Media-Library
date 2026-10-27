import { Outlet, createFileRoute } from '@tanstack/solid-router'
import { AppShell } from '../components/shell/AppShell'
import { requireSession } from '../lib/session/query'
import { readSidebarOpen } from '../lib/sidebar-read'

// The one layout every signed-in `/app` page renders in (DESIGN.md §18, UX-002). It also holds
// the one sign-in check: a signed-out visit goes to sign-in with `next`, so a link from a push or
// an email lands where it pointed once you are in (UX-011).
export const Route = createFileRoute('/_shell')({
  // Asked once per tab through the query cache, not on every navigation.
  beforeLoad: async ({ location, context }) => ({
    session: await requireSession(context.queryClient, location.href),
  }),
  loader: ({ context }) => ({
    session: {
      displayName: context.session.displayName,
      handle: context.session.handle,
      avatarUrl: context.session.avatarUrl ?? null,
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
