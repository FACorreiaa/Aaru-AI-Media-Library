import { Link, createFileRoute } from '@tanstack/solid-router'
import { AppHeader } from '../components/AppHeader'
import { PlanCard } from '../components/PlanCard'
import { getPlan } from '../lib/plans/server'
import { requireSession } from '../lib/session/query'

// OUT-004: one agent request, where its push notification opens.
export const Route = createFileRoute('/app_/plans/$id')({
  head: () => ({ meta: [{ title: 'Request · Aaru' }] }),
  beforeLoad: async ({ context }) => {
    await requireSession(context.queryClient)
  },
  loader: ({ params }) => getPlan({ data: { id: params.id } }),
  component: PlanPage,
})

function PlanPage() {
  const plan = Route.useLoaderData()
  return (
    <div class="min-h-[100dvh]">
      <AppHeader />
      <main class="mx-auto max-w-2xl px-4 pb-16 md:px-8">
        <Link to="/app" class="mt-6 inline-block text-sm text-accent">
          ← Home
        </Link>
        <div class="mt-4">
          <PlanCard plan={plan()} />
        </div>
      </main>
    </div>
  )
}
