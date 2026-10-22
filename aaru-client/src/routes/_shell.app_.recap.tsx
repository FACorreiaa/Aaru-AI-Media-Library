import { Link, createFileRoute, useNavigate } from '@tanstack/solid-router'
import type { SearchSchemaInput } from '@tanstack/solid-router'
import { Match, Switch, createEffect, createSignal, on } from 'solid-js'
import { optionalInt } from '../lib/search-params'
import { RecapStory } from '../components/recap/RecapStory'
import { Alert, AlertDescription } from '~/components/ui'
import { cards } from '../lib/recap/deck'
import type { RecapCard } from '../lib/recap/deck'
import { periodLabel } from '../lib/recap/model'
import type { Stats } from '../lib/recap/model'
import { useAppShell } from '../components/shell/context'
import { prefersReducedMotion } from '../lib/reduced-motion'
import { myStatsQuery } from '../lib/queries'

// GAM-006a on the web: the Recap story for `?year=` and optional `?month=`, the twin of the
// Apple apps' `RecapView`. Stats load in the browser, which knows the viewer's time zone.
export const Route = createFileRoute('/_shell/app_/recap')({
  head: () => ({ meta: [{ title: 'Recap · Aaru' }] }),
  validateSearch: (
    search: { year?: number; month?: number } & SearchSchemaInput,
  ): { year: number; month?: number } => ({
    year: optionalInt(search.year, 1900, 2200) ?? new Date().getFullYear(),
    month: optionalInt(search.month, 1, 12),
  }),
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
  const shell = useAppShell()
  const [open, setOpen] = createSignal(true)

  // UX-081: a new ?year/&month loads its own recap; a stale answer never replaces a newer one.
  let request = 0
  createEffect(
    on(
      () => [search().year, search().month] as const,
      async ([year, month]) => {
        const mine = ++request
        setState({ kind: 'loading' })
        setOpen(true)
        try {
          const stats = await queryClient.query(
            myStatsQuery({
              year,
              month,
              tz: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
            }),
          )
          if (mine === request)
            setState({ kind: 'ready', stats, deck: cards(stats) })
        } catch (err) {
          if (mine === request)
            setState({
              kind: 'failed',
              message:
                err instanceof Error
                  ? err.message
                  : 'Your recap could not be loaded.',
            })
        }
      },
    ),
  )

  /** Close goes back where the recap was opened from (Home, Insights, Your data), else Home,
   *  once the story's exit has played. */
  function close() {
    setOpen(false)
    const leave = () => {
      if (shell.previous()) window.history.back()
      else void navigate({ to: '/app' })
    }
    if (prefersReducedMotion()) leave()
    else window.setTimeout(leave, 200)
  }

  const ready = () => {
    const current = state()
    return current.kind === 'ready' ? current : null
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Your {label()}
        </h1>
        <Switch>
          <Match when={state().kind === 'loading'}>
            <p class="mt-4 text-muted">Gathering your {label()}…</p>
          </Match>
          <Match when={state().kind === 'failed' && state()}>
            {(failed) => (
              <Alert variant="destructive" class="mt-4">
                <AlertDescription>
                  {(failed() as { message: string }).message}
                </AlertDescription>
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
                open={open()}
                stats={current().stats}
                deck={current().deck}
                onClose={close}
              />
            )}
          </Match>
        </Switch>
      </div>
    </div>
  )
}
