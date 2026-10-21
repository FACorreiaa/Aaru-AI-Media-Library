import { Link, createFileRoute } from '@tanstack/solid-router'
import { PlanCard } from '../components/PlanCard'
import { getPlan } from '../lib/plans/server'

// OUT-004: one agent request, where its push notification opens.
export const Route = createFileRoute('/_shell/app_/plans/$id')({
  head: () => ({ meta: [{ title: 'Request · Aaru' }] }),
  loader: ({ params }) => getPlan({ data: { id: params.id } }),
  component: PlanPage,
})

function PlanPage() {
  const plan = Route.useLoaderData()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <Link to="/app" class="mt-6 inline-block text-sm text-accent">
          ← Home
        </Link>
        <div class="mt-4">
          <PlanCard plan={plan()} />
        </div>
      </div>
    </div>
  )
}
