import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import type { SearchSchemaInput } from '@tanstack/solid-router'
import { Match, Switch, createSignal, onMount } from 'solid-js'
import { optionalInt } from '../lib/search-params'
import { AppHeader } from '../components/AppHeader'
import { RecapStory } from '../components/recap/RecapStory'
import { Alert } from '../components/ui/alert'
import { cards } from '../lib/recap/deck'
import type { RecapCard } from '../lib/recap/deck'
import { periodLabel } from '../lib/recap/model'
import type { Stats } from '../lib/recap/model'
import { myStatsQuery } from '../lib/queries'
import { requireSession } from '../lib/session/query'

// GAM-006a on the web: the Recap story for `?year=` and optional `?month=`, the twin of the
// Apple apps' `RecapView`. Stats load in the browser, which knows the viewer's time zone.
export const Route = createFileRoute('/app_/recap')({
  head: () => ({ meta: [{ title: 'Recap · Aaru' }] }),
  validateSearch: (
    search: { year?: number; month?: number } & SearchSchemaInput,
  ): { year: number; month?: number } => ({
    year: optionalInt(search.year, 1900, 2200) ?? new Date().getFullYear(),
    month: optionalInt(search.month, 1, 12),
  }),
  beforeLoad: async ({ context }) => {
    await requireSession(context.queryClient)
  },
  component: Recap,
})

function Recap() {
  const search = Route.useSearch()
  const { queryClient } = Route.useRouteContext()()
  const navigate = useNavigate()
  const [state, setState] = createSignal<
    | { kind: 'loading' }
    | { kind: 'ready'; stats: Stats; deck: RecapCard[] }
    | { kind: 'failed'; message: string }
  >({ kind: 'loading' })
  const label = () => periodLabel(search())

  onMount(async () => {
    try {
      const stats = await queryClient.query(
        myStatsQuery({
          year: search().year,
          month: search().month,
          tz: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        }),
      )
      setState({ kind: 'ready', stats, deck: cards(stats) })
    } catch (err) {
      setState({
        kind: 'failed',
        message:
          err instanceof Error
            ? err.message
            : 'Your recap could not be loaded.',
      })
    }
  })

  const ready = () => {
    const current = state()
    return current.kind === 'ready' ? current : null
  }

  return (
    <div class="min-h-[100dvh]">
      <AppHeader />
      <main class="mx-auto max-w-xl px-4 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Your {label()}
        </h1>
        <Switch>
          <Match when={state().kind === 'loading'}>
            <p class="mt-4 text-muted">Gathering your {label()}…</p>
          </Match>
          <Match when={state().kind === 'failed' && state()}>
            {(failed) => (
              <Alert class="mt-4">
                {(failed() as { message: string }).message}
              </Alert>
            )}
          </Match>
          <Match when={ready()?.deck.length === 0}>
            <p class="mt-4 text-muted">
              Nothing tracked in {label()} yet. Tick an episode or finish a
              title, and it will show up here.
            </p>
            <Link
              to="/app"
              class="mt-6 inline-block font-medium text-accent hover:underline"
            >
              Back to Home
            </Link>
          </Match>
          <Match when={ready()}>
            {(current) => (
              <RecapStory
                stats={current().stats}
                deck={current().deck}
                onClose={() => navigate({ to: '/app' })}
              />
            )}
          </Match>
        </Switch>
      </main>
    </div>
  )
}
