import { createFileRoute, useNavigate, useRouter } from '@tanstack/solid-router'
import {
  Match,
  Show,
  Switch,
  createEffect,
  createSignal,
  onCleanup,
} from 'solid-js'
import { Button } from '~/components/ui'
import { BackLink } from '../components/shell/BackLink'
import { useAssistantTitle } from '../components/shell/context'
import { WorldLegend, WorldMap, WorldProgress } from '../components/WorldMap'
import { shareWorld } from '../components/world/share'
import {
  countLabel,
  isReady,
  kindsLabel,
  missingCount,
} from '../lib/title/world'
import { loadWorld, planWorldRest } from '../lib/title/worldServer'

// GRAPH-007: one World, whole: its name, how far the viewer is, the map, a share image of their
// path, and "Add the rest". The server builds and lays out every World; this page only draws it.
// Catalog data and the viewer's own marks: nothing here is a recommendation.

const RETRY_MS = 4000
const TRIES = 6

export const Route = createFileRoute('/_shell/app_/world/$titleId')({
  loader: ({ params }) => loadWorld({ data: { titleId: params.titleId } }),
  head: ({ loaderData }) => ({
    meta: [{ title: `${loaderData?.name ?? 'World'} · Aaru` }],
  }),
  component: WorldPage,
})

function WorldPage() {
  const world = Route.useLoaderData()
  const params = Route.useParams()
  useAssistantTitle(() => params().titleId)
  const router = useRouter()
  const navigate = useNavigate()
  const [planning, setPlanning] = createSignal(false)
  const [sharing, setSharing] = createSignal(false)
  const [note, setNote] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  // A World still being built is asked for again a few times, then left with a way to look again.
  let tries = TRIES
  let retry: ReturnType<typeof setTimeout> | undefined
  createEffect(() => {
    clearTimeout(retry)
    if (world().state === 'building' && tries > 1) {
      tries -= 1
      retry = setTimeout(() => void router.invalidate(), RETRY_MS)
    }
  })
  onCleanup(() => clearTimeout(retry))

  /** The titles the viewer lacks as a capture to review; nothing is added until Approve. */
  const addRest = async () => {
    setPlanning(true)
    setProblem(null)
    try {
      const job = await planWorldRest({ data: { titleId: params().titleId } })
      await navigate({ to: '/app/imports/$id', params: { id: job.id } })
    } catch (error) {
      setProblem(error instanceof Error ? error.message : String(error))
    } finally {
      setPlanning(false)
    }
  }

  const share = async () => {
    setSharing(true)
    setNote(null)
    try {
      if ((await shareWorld(world())) === 'downloaded')
        setNote('Saved as an image.')
    } catch (error) {
      setNote(
        error instanceof Error ? error.message : 'The image could not be made.',
      )
    } finally {
      setSharing(false)
    }
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <BackLink to="/app/worlds" label="Worlds" class="-ml-1" />
        <Switch>
          <Match when={isReady(world())}>
            <div class="mt-4 flex flex-wrap items-end justify-between gap-4">
              <div class="min-w-0">
                <p class="eyebrow">World</p>
                <h1 class="mt-1 font-display text-3xl font-semibold">
                  {world().name}
                </h1>
                <p class="mt-2 flex flex-wrap items-baseline gap-x-2">
                  <span class="font-semibold tabular-nums">
                    {countLabel(world().finished, world().total)}
                  </span>
                  <span class="text-sm text-muted">
                    {kindsLabel(world().kinds)}
                  </span>
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-3">
                <Button disabled={sharing()} onClick={() => void share()}>
                  {sharing() ? 'Drawing…' : 'Share my path'}
                </Button>
                <Show when={missingCount(world()) > 0}>
                  <Button
                    variant="outline"
                    disabled={planning()}
                    onClick={() => void addRest()}
                  >
                    {planning()
                      ? 'Planning…'
                      : `Add the rest (${missingCount(world())})`}
                  </Button>
                </Show>
              </div>
            </div>
            <div class="mt-4 max-w-md">
              <WorldProgress
                finished={world().finished}
                total={world().total}
              />
            </div>
            <Show when={world().truncated}>
              <p class="mt-3 text-sm text-muted">
                This universe is larger than one map holds. It is shown from its
                first title.
              </p>
            </Show>
            <Show when={world().partial}>
              <p class="mt-3 text-sm text-muted">
                Some titles are still being found.{' '}
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
            <Show when={note()}>
              {(message) => (
                <p role="status" class="mt-3 text-sm text-muted">
                  {message()}
                </p>
              )}
            </Show>
            <Show when={problem()}>
              {(message) => (
                <p role="alert" class="mt-3 text-sm text-danger">
                  {message()}
                </p>
              )}
            </Show>
            <div class="mt-6">
              <WorldMap world={world()} />
            </div>
            <div class="mt-4 flex flex-wrap items-center justify-between gap-3">
              <WorldLegend />
              <p class="text-xs text-muted">
                Relations from AniList, TMDB and Wikidata.
              </p>
            </div>
          </Match>
          <Match when={world().state === 'building'}>
            <div class="mt-16 text-center" role="status">
              <p class="font-display text-2xl font-medium">
                Mapping this world…
              </p>
              <p class="mt-2 text-muted">
                Aaru is reading how these stories connect. It takes a moment the
                first time.
              </p>
              <Button
                variant="outline"
                class="mt-6"
                onClick={() => void router.invalidate()}
              >
                Look again
              </Button>
            </div>
          </Match>
          <Match when={true}>
            <div class="mt-16 text-center">
              <p class="font-display text-2xl font-medium">No world here</p>
              <p class="mt-2 text-muted">
                This title is not part of a larger story the catalog knows.
              </p>
            </div>
          </Match>
        </Switch>
      </div>
    </div>
  )
}
