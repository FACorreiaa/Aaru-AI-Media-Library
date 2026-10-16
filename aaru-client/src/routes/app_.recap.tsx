import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
} from '@tanstack/solid-router'
import { Match, Switch, createSignal, onMount } from 'solid-js'
import { z } from 'zod'
import { AppHeader } from '../components/AppHeader'
import { RecapStory } from '../components/recap/RecapStory'
import { cards, periodLabel } from '../lib/recap/model'
import type { RecapCard, Stats } from '../lib/recap/model'
import { getStats } from '../lib/recap/server'
import { getSession } from '../lib/session/session'

// GAM-006a on the web: the Recap story for `?year=` and optional `?month=`, the twin of the
// Apple apps' `RecapView`. Stats load in the browser, which knows the viewer's time zone.
export const Route = createFileRoute('/app_/recap')({
  head: () => ({ meta: [{ title: 'Recap · Aaru' }] }),
  validateSearch: z.object({
    year: z.coerce
      .number()
      .int()
      .min(1900)
      .max(2200)
      .catch(new Date().getFullYear()),
    month: z.coerce.number().int().min(1).max(12).optional().catch(undefined),
  }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
  },
  component: Recap,
})

function Recap() {
  const search = Route.useSearch()
  const navigate = useNavigate()
  const [state, setState] = createSignal<
    | { kind: 'loading' }
    | { kind: 'ready'; stats: Stats; deck: RecapCard[] }
    | { kind: 'failed'; message: string }
  >({ kind: 'loading' })
  const label = () => periodLabel(search())

  onMount(async () => {
    try {
      const stats = await getStats({
        data: {
          year: search().year,
          month: search().month,
          tz: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        },
      })
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
              <p
                role="alert"
                class="mt-4 rounded-[14px] bg-danger/10 px-4 py-3 text-sm text-danger"
              >
                {(failed() as { message: string }).message}
              </p>
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
