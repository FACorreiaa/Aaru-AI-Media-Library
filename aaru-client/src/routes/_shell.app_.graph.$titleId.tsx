import { createFileRoute, useNavigate, useRouter } from '@tanstack/solid-router'
import { useAssistantTitle } from '../components/shell/context'
import { Show, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import { BackLink } from '../components/shell/BackLink'
import { RelationGraphCanvas } from '../components/RelationGraphCanvas'
import { Segmented } from '../components/Segmented'
import { loadRelations, planChain, resolveTitle } from '../lib/title/server'
import { previewParams } from '../lib/title/preview'
import { centreOf } from '../lib/title/relations'
import type { RelationNode, RelationOrder } from '../lib/title/relations'

// GRAPH-002: `RelationGraph` on the web. The server places every title (`rank` is the column,
// `lane` the row, 0 the main chain); this page only draws them, with no layout library. A title
// opens its page; Centre walks the graph out from it.

export const Route = createFileRoute('/_shell/app_/graph/$titleId')({
  validateSearch: (search): { order?: RelationOrder } =>
    search.order === 'story' ? { order: 'story' } : {},
  loaderDeps: ({ search }) => ({ order: search.order }),
  loader: ({ params, deps }) =>
    loadRelations({ data: { titleId: params.titleId, order: deps.order } }),
  head: ({ loaderData }) => ({
    meta: [
      {
        title: `${(loaderData && centreOf(loaderData)?.ref.title) ?? 'Related'} · Aaru`,
      },
    ],
  }),
  component: GraphPage,
})

function GraphPage() {
  const graph = Route.useLoaderData()
  const params = Route.useParams()
  useAssistantTitle(() => params().titleId)
  const router = useRouter()
  const navigate = useNavigate()
  const [centring, setCentring] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  const setOrder = (order: RelationOrder) =>
    void navigate({
      to: '/app/graph/$titleId',
      params: { titleId: params().titleId },
      search: order === 'story' ? { order } : {},
      replace: true,
    })

  const [planning, setPlanning] = createSignal(false)
  const hasChain = () => graph().nodes.filter((n) => n.mainChain).length > 1
  /** GRAPH-003: the main chain as a capture to review; nothing is added until Approve. */
  const addChain = async () => {
    setPlanning(true)
    setProblem(null)
    try {
      const job = await planChain({
        data: { titleId: params().titleId, order: graph().order },
      })
      await navigate({ to: '/app/imports/$id', params: { id: job.id } })
    } catch (error) {
      setProblem(error instanceof Error ? error.message : String(error))
    } finally {
      setPlanning(false)
    }
  }

  const centreOn = async (node: RelationNode) => {
    const preview = previewParams({
      type: node.ref.type,
      ids: node.ref.ids ?? {},
    })
    if (!preview) return
    setCentring(node.key)
    setProblem(null)
    try {
      const found = await resolveTitle({ data: preview })
      await navigate({
        to: '/app/graph/$titleId',
        params: { titleId: found.title.id },
      })
    } catch (error) {
      setProblem(error instanceof Error ? error.message : String(error))
    } finally {
      setCentring(null)
    }
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/library" label="Library" class="-ml-1" />
        <div class="mt-4 flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="eyebrow">Related</p>
            <h1 class="mt-1 font-display text-3xl font-semibold">
              {centreOf(graph())?.ref.title ?? 'Related titles'}
            </h1>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <Show when={hasChain()}>
              <Button
                variant="outline"
                disabled={planning()}
                onClick={() => void addChain()}
              >
                {planning() ? 'Planning…' : 'Add the chain'}
              </Button>
            </Show>
            <Show when={graph().storyOrderAvailable}>
              <Segmented
                label="Order"
                value={graph().order}
                onChange={setOrder}
                options={[
                  { value: 'release', label: 'Release order' },
                  { value: 'story', label: 'Story order' },
                ]}
              />
            </Show>
          </div>
        </div>
        <Show when={graph().partial}>
          <p class="mt-3 text-sm text-muted">
            Some related titles are still being found.{' '}
            <Button
              variant="link"
              size="sm"
              class="h-auto p-0"
              onClick={() => void router.invalidate()}
            >
              Look again
            </Button>
          </p>
        </Show>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-3 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>

        <Show
          when={graph().nodes.length > 1}
          fallback={
            <p class="mt-8 text-muted">
              No related titles are known for this one yet.
            </p>
          }
        >
          <RelationGraphCanvas
            graph={graph()}
            label="Related titles in order"
            centring={centring()}
            onCentre={(node) => void centreOn(node)}
          />
          <p class="mt-4 text-xs text-muted">
            Relations from AniList, TMDB and Wikidata.
          </p>
        </Show>
      </div>
    </div>
  )
}
