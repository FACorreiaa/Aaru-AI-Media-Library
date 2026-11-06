import { createFileRoute, useNavigate, useRouter } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import { BackLink } from '../components/shell/BackLink'
import { RelatedCard } from '../components/RelatedTitles'
import { Segmented } from '../components/Segmented'
import { loadRelations, planChain, resolveTitle } from '../lib/title/server'
import { previewParams } from '../lib/title/preview'
import { centreOf, edgeLabel } from '../lib/title/relations'
import type {
  RelationEdge,
  RelationNode,
  RelationOrder,
} from '../lib/title/relations'

// GRAPH-002: `RelationGraph` on the web. The server places every title (`rank` is the column,
// `lane` the row, 0 the main chain); this page only draws them, with no layout library. A title
// opens its page; Centre walks the graph out from it.

const COLUMN = 136
const ROW = 236
const CARD = 96
/** Where an edge meets a card: halfway down a 2:3 poster. */
const ANCHOR_Y = 72
const PAD = 16

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
  const router = useRouter()
  const navigate = useNavigate()
  const [centring, setCentring] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  const byKey = createMemo(
    () => new Map(graph().nodes.map((n) => [n.key, n] as const)),
  )
  const width = () =>
    Math.max(...graph().nodes.map((n) => n.rank), 0) * COLUMN + CARD + PAD * 2
  const height = () =>
    Math.max(...graph().nodes.map((n) => n.lane), 0) * ROW + ROW + PAD

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
          <div class="mt-6 overflow-x-auto rounded-card border border-line bg-surface/40">
            <div
              class="relative"
              style={{ width: `${width()}px`, height: `${height()}px` }}
            >
              <svg
                class="pointer-events-none absolute inset-0 text-line"
                width={width()}
                height={height()}
                aria-hidden="true"
              >
                <For each={graph().edges}>
                  {(edge) => <EdgePath edge={edge} nodes={byKey()} />}
                </For>
              </svg>
              <ol aria-label="Related titles in order">
                <For each={graph().nodes}>
                  {(node) => (
                    <li
                      class="absolute"
                      style={{
                        left: `${PAD + node.rank * COLUMN}px`,
                        top: `${PAD + node.lane * ROW}px`,
                        width: `${CARD}px`,
                      }}
                    >
                      <div
                        class={
                          node.centre
                            ? 'rounded-field ring-2 ring-accent ring-offset-2 ring-offset-paper'
                            : ''
                        }
                      >
                        <RelatedCard
                          node={node}
                          startHere={graph().startHere === node.key}
                        />
                      </div>
                      <Show when={!node.centre}>
                        <Button
                          variant="link"
                          size="sm"
                          class="h-auto p-0 text-xs"
                          disabled={centring() !== null}
                          onClick={() => void centreOn(node)}
                        >
                          {centring() === node.key ? 'Opening…' : 'Centre'}
                        </Button>
                      </Show>
                    </li>
                  )}
                </For>
              </ol>
            </div>
          </div>
          <p class="mt-4 text-xs text-muted">
            Relations from AniList, TMDB and Wikidata.
          </p>
        </Show>
      </div>
    </div>
  )
}

/** One edge: from the right of the earlier card to the left of the later one, or straight down
 * between two cards in one column. The main chain is drawn solid, everything else dashed and
 * labelled. */
function EdgePath(props: {
  edge: RelationEdge
  nodes: Map<string, RelationNode>
}) {
  const ends = () => {
    const from = props.nodes.get(props.edge.from)
    const to = props.nodes.get(props.edge.to)
    if (!from || !to) return null
    const [a, b] =
      from.rank < to.rank || (from.rank === to.rank && from.lane <= to.lane)
        ? [from, to]
        : [to, from]
    const x = (n: RelationNode) => PAD + n.rank * COLUMN
    const y = (n: RelationNode) => PAD + n.lane * ROW
    if (a.rank === b.rank) {
      const cx = x(a) + CARD / 2
      return {
        d: `M ${cx} ${y(a) + CARD * 1.5} L ${cx} ${y(b)}`,
        mx: cx + 4,
        my: (y(a) + CARD * 1.5 + y(b)) / 2,
      }
    }
    const x1 = x(a) + CARD
    const y1 = y(a) + ANCHOR_Y
    const x2 = x(b)
    const y2 = y(b) + ANCHOR_Y
    const bend = (x2 - x1) / 2
    return {
      d: `M ${x1} ${y1} C ${x1 + bend} ${y1}, ${x2 - bend} ${y2}, ${x2} ${y2}`,
      mx: (x1 + x2) / 2,
      my: (y1 + y2) / 2 - 4,
    }
  }
  const main = () =>
    props.edge.relation === 'sequel' || props.edge.relation === 'prequel'
  return (
    <Show when={ends()}>
      {(e) => (
        <g>
          <path
            d={e().d}
            fill="none"
            stroke="currentColor"
            stroke-width={main() ? 2 : 1.25}
            stroke-dasharray={main() ? undefined : '4 4'}
            class={main() ? 'text-accent' : undefined}
          />
          <Show when={edgeLabel(props.edge.relation)}>
            {(label) => (
              <text
                x={e().mx}
                y={e().my}
                class="fill-muted text-[10px]"
                text-anchor="middle"
              >
                {label()}
              </text>
            )}
          </Show>
        </g>
      )}
    </Show>
  )
}
