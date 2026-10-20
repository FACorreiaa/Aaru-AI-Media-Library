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
import { z } from 'zod'
import { AppHeader } from '../components/AppHeader'
import { StatsPanel } from '../components/StatsPanel'
import {
  SPANS,
  insightsLabel,
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

// Insights on the web: a month, a year, or all time in numbers, the browsable twin of the
// Recap story. Stats load in the browser, which knows the viewer's time zone and "this month".
export const Route = createFileRoute('/app_/insights')({
  head: () => ({ meta: [{ title: 'Insights · Aaru' }] }),
  validateSearch: z.object({
    span: z.enum(['month', 'year', 'all']).optional().catch(undefined),
    year: z.coerce
      .number()
      .int()
      .min(1900)
      .max(2200)
      .optional()
      .catch(undefined),
    month: z.coerce.number().int().min(1).max(12).optional().catch(undefined),
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
          <div
            class="flex overflow-hidden rounded-full border border-line text-sm"
            role="group"
            aria-label="Period"
          >
            <For each={SPANS}>
              {(option) => (
                <button
                  type="button"
                  aria-pressed={period()?.span === option.span}
                  class="px-4 py-1.5"
                  classList={{
                    'bg-surface font-semibold': period()?.span === option.span,
                  }}
                  onClick={() => {
                    const p = period()
                    const current = now()
                    if (p && current) go(withSpan(p, option.span, current))
                  }}
                >
                  {option.label}
                </button>
              )}
            </For>
          </div>
          <Show when={period()}>
            {(p) => (
              <div class="flex items-center gap-2">
                <Show when={p().span !== 'all'}>
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
                <Show when={p().span !== 'all'}>
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
            {(message) => (
              <p
                role="alert"
                class="mt-6 rounded-[14px] bg-danger/10 px-4 py-3 text-sm text-danger"
              >
                {message()}
              </p>
            )}
          </Match>
          <Match when={ready()}>
            {(stats) => (
              <Show
                when={!isEmpty(stats())}
                fallback={
                  <p class="mt-10 text-muted">
                    {period()?.span === 'all'
                      ? 'Nothing tracked yet.'
                      : `Nothing tracked in ${insightsLabel(period() ?? { span: 'all' })} yet.`}{' '}
                    Tick an episode or finish a title, and it will show up here.
                  </p>
                }
              >
                <StatsPanel
                  stats={stats()}
                  period={period() ?? { span: 'all' }}
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
