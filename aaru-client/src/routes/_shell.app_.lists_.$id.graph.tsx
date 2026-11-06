import { createFileRoute } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { BackLink } from '../components/shell/BackLink'
import { RelationGraphCanvas } from '../components/RelationGraphCanvas'
import { getListGraph } from '../lib/lists/server'

// GRAPH-004: a roadmap list as a graph: its titles left to right in step order, titles read side by
// side in one column, optional ones hanging under the title before them. The server places them.
export const Route = createFileRoute('/_shell/app_/lists_/$id/graph')({
  loader: ({ params }) => getListGraph({ data: { id: params.id } }),
  head: () => ({ meta: [{ title: 'Roadmap graph · Aaru' }] }),
  component: ListGraphPage,
})

function ListGraphPage() {
  const graph = Route.useLoaderData()
  const params = Route.useParams()
  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to={`/app/lists/${params().id}`} label="List" class="-ml-1" />
        <p class="eyebrow mt-4">Roadmap</p>
        <h1 class="mt-1 font-display text-3xl font-semibold">In order</h1>
        <Show
          when={graph().nodes.length > 0}
          fallback={<p class="mt-8 text-muted">This list is empty.</p>}
        >
          <RelationGraphCanvas graph={graph()} label="The list in order" />
        </Show>
      </div>
    </div>
  )
}
