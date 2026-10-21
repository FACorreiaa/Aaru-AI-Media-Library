import { createFileRoute, redirect } from '@tanstack/solid-router'
import {
  For,
  Match,
  Show,
  Switch,
  createEffect,
  createSignal,
  onMount,
} from 'solid-js'
import { optionalEnum, optionalInt } from '../lib/search-params'
import { AppHeader } from '../components/AppHeader'
import { StatsPanel } from '../components/StatsPanel'
import { MusicInsights } from '../components/music/MusicInsights'
import { Alert } from '../components/ui/alert'
import {
  SegmentedControl,
  SegmentedControlItem,
} from '../components/ui/segmented-control'
import {
  SPANS,
  insightsLabel,
  isRolling,
  periodFromSearch,
  shift,
  statsQuery,
  toSearch,
  withSpan,
} from '../lib/insights/model'
import type { InsightsPeriod } from '../lib/insights/model'
import { isEmpty } from '../lib/recap/model'
import type { Stats } from '../lib/recap/model'
import { getStats } from '../lib/recap/server'
import { getSession } from '../lib/session/session'

// Insights on the web: the last 7 or 30 days, a month, a year, or all time in numbers, the browsable twin of the
// Recap story. Stats load in the browser, which knows the viewer's time zone and "this month".
export const Route = createFileRoute('/app_/insights')({
  head: () => ({ meta: [{ title: 'Insights · Aaru' }] }),
  validateSearch: (
    search,
  ): {
    span?: 'last7' | 'last30' | 'month' | 'year' | 'all'
    year?: number
    month?: number
  } => ({
    span: optionalEnum(search.span, [
      'last7',
      'last30',
      'month',
      'year',
      'all',
    ]),
    year: optionalInt(search.year, 1900, 2200),
    month: optionalInt(search.month, 1, 12),
  }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  component: Insights,
})

type State =
  | { kind: 'loading' }
  | { kind: 'ready'; stats: Stats }
  | { kind: 'failed'; message: string }

function Insights() {
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const [now, setNow] = createSignal<Date | null>(null)
  const [period, setPeriod] = createSignal<InsightsPeriod | null>(null)
  const [state, setState] = createSignal<State>({ kind: 'loading' })
  let latest = 0

  // MUS-008: listening for the same period, apart from the library's numbers.
  const music = (stats: Stats) => {
    const p = period()
    const heard = stats.music
    if (!p || !heard) return undefined
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
    return <MusicInsights music={heard} query={statsQuery(p, tz)} />
  }

  onMount(() => setNow(new Date()))

  createEffect(() => {
    const current = now()
    if (!current) return
    const next = periodFromSearch(search(), current)
    setPeriod(next)
    const ticket = ++latest
    setState({ kind: 'loading' })
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
    getStats({ data: statsQuery(next, tz) }).then(
      (stats) => {
        if (ticket === latest) setState({ kind: 'ready', stats })
      },
      (err: unknown) => {
        if (ticket === latest)
          setState({
            kind: 'failed',
            message:
              err instanceof Error
                ? err.message
                : 'Your stats could not be loaded.',
          })
      },
    )
  })

  function go(next: InsightsPeriod | null) {
    if (next) void navigate({ search: toSearch(next), replace: true })
  }

  const ready = () => {
    const current = state()
    return current.kind === 'ready' ? current.stats : null
  }
  const failed = () => {
    const current = state()
    return current.kind === 'failed' ? current.message : null
  }
  const step = (direction: 1 | -1) => {
    const p = period()
    const current = now()
    return p && current ? shift(p, direction, current) : null
  }

  const arrow =
    'grid h-9 w-9 place-items-center rounded-full border border-line text-ink hover:bg-surface disabled:opacity-30 disabled:hover:bg-transparent'

  return (
    <div class="min-h-[100dvh]">
      <AppHeader />
      <main class="mx-auto max-w-3xl px-4 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Insights
        </h1>

        <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
          <SegmentedControl
            class="flex overflow-hidden rounded-full border border-line text-sm"
            aria-label="Period"
            // '' until the period is known: controlled, with nothing chosen yet.
            value={period()?.span ?? ''}
            onChange={(span) => {
              const p = period()
              const current = now()
              const option = SPANS.find((o) => o.span === span)
              if (p && current && option) go(withSpan(p, option.span, current))
            }}
          >
            <For each={SPANS}>
              {(option) => (
                <SegmentedControlItem
                  value={option.span}
                  variant="surface"
                  class="px-4 py-1.5"
                >
                  {option.label}
                </SegmentedControlItem>
              )}
            </For>
          </SegmentedControl>
          <Show when={period()}>
            {(p) => (
              <div class="flex items-center gap-2">
                <Show when={p().span !== 'all' && !isRolling(p().span)}>
                  <button
                    type="button"
                    class={arrow}
                    aria-label="Earlier"
                    disabled={!step(-1)}
                    onClick={() => go(step(-1))}
                  >
                    ‹
                  </button>
                </Show>
                <span class="min-w-[8.5rem] text-center font-medium">
                  {insightsLabel(p())}
                </span>
                <Show when={p().span !== 'all' && !isRolling(p().span)}>
                  <button
                    type="button"
                    class={arrow}
                    aria-label="Later"
                    disabled={!step(1)}
                    onClick={() => go(step(1))}
                  >
                    ›
                  </button>
                </Show>
              </div>
            )}
          </Show>
        </div>

        <Switch>
          <Match when={failed()}>
            {(message) => <Alert class="mt-6">{message()}</Alert>}
          </Match>
          <Match when={ready()}>
            {(stats) => (
              <Show
                when={!isEmpty(stats())}
                fallback={
                  <>
                    <p class="mt-10 text-muted">
                      {period()?.span === 'all'
                        ? 'Nothing tracked yet.'
                        : period()?.span === 'last7'
                          ? 'Nothing tracked in the last 7 days.'
                          : period()?.span === 'last30'
                            ? 'Nothing tracked in the last 30 days.'
                            : `Nothing tracked in ${insightsLabel(period() ?? { span: 'all' })} yet.`}{' '}
                      Tick an episode or finish a title, and it will show up
                      here.
                    </p>
                    {music(stats())}
                  </>
                }
              >
                <StatsPanel
                  stats={stats()}
                  period={period() ?? { span: 'all' }}
                  music={music(stats())}
                />
              </Show>
            )}
          </Match>
          <Match when={state().kind === 'loading'}>
            <p class="mt-10 text-muted">Counting…</p>
          </Match>
        </Switch>
      </main>
    </div>
  )
}
