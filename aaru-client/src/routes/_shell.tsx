import { Outlet, createFileRoute, redirect } from '@tanstack/solid-router'
import { AppShell } from '../components/shell/AppShell'
import { getSession } from '../lib/session/session'
import { readSidebarOpen } from '../lib/sidebar-read'

// The one layout every signed-in `/app` page renders in (DESIGN.md §18, UX-002). It also holds
// the one sign-in check: a signed-out visit goes to sign-in with `next`, so a link from a push or
// an email lands where it pointed once you are in (UX-011).
export const Route = createFileRoute('/_shell')({
  beforeLoad: async ({ location }) => {
    const session = await getSession()
    if (!session.signedIn)
      throw redirect({ to: '/sign-in', search: { next: location.href } })
    return { session }
  },
  loader: ({ context }) => ({
    session: {
      displayName: context.session.displayName,
      handle: context.session.handle,
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
