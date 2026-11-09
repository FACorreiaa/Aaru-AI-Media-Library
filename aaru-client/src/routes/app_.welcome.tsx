import { createFileRoute, redirect } from '@tanstack/solid-router'
import { OnboardingFlow } from '../components/onboarding/OnboardingFlow'
import { safeNext } from '../lib/oauth/model'
import { welcomeNext } from '../lib/onboarding/next'
import { optionalString } from '../lib/search-params'
import { requireSession } from '../lib/session/query'

// ONB-001: a new account's first run (DESIGN.md §0a), full screen and outside the app shell,
// at `/app/welcome?next=…`. The shell sends a pending account here; once the flow is finished
// or skipped this address sends you straight on to `next`.
export const Route = createFileRoute('/app_/welcome')({
  head: () => ({ meta: [{ title: 'Welcome · Aaru' }] }),
  validateSearch: (search): { next?: string } => ({
    next: optionalString(search.next),
  }),
  beforeLoad: async ({ search, location, context }) => {
    const session = await requireSession(context.queryClient, location.href)
    const next = welcomeNext(safeNext(search.next))
    if (!session.onboardingPending) throw redirect({ href: next })
    return { next }
  },
  component: Welcome,
})

function Welcome() {
  const context = Route.useRouteContext()
  return (
    <main class="min-h-dvh bg-paper text-ink">
      <OnboardingFlow next={context().next} />
    </main>
  )
}
