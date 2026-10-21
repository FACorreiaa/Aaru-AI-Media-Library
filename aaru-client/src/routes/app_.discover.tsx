import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { Show, createSignal, onMount } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { DiscoverRows } from '../components/DiscoverRows'
import { Alert } from '../components/ui/alert'
import { CREDITS, TMDB_URL } from '../lib/credits'
import { localDayKey } from '../lib/calendar/model'
import type { DiscoverRow } from '../lib/home/model'
import { getDiscover } from '../lib/home/server'
import { getSession } from '../lib/session/session'

// Discover on the web, the twin of the Apple apps' Discover tab: the same public rows Home
// shows under the user's own (DISC-001), on a page of their own, each card addable in place.
// The server names and orders the rows and marks the titles already on the shelf.
export const Route = createFileRoute('/app_/discover')({
  head: () => ({ meta: [{ title: 'Discover · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
    return { session }
  },
  loader: () =>
    getDiscover().then(
      (rows) => ({ rows, problem: null }),
      (err: unknown) => ({
        rows: [] as DiscoverRow[],
        problem:
          err instanceof Error
            ? err.message
            : 'Discover is not available right now.',
      }),
    ),
  component: DiscoverPage,
})

const ANILIST = CREDITS.find((c) => c.name === 'AniList')?.href
const OPEN_LIBRARY = CREDITS.find((c) => c.name === 'Open Library')?.href

function DiscoverPage() {
  const loaded = Route.useLoaderData()
  const [rows, setRows] = createSignal<DiscoverRow[]>(loaded().rows)
  const [today, setToday] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(loaded().problem)

  // The release badges count days from the viewer's today, which only the browser knows.
  onMount(() => setToday(localDayKey(new Date())))

  return (
    <div class="min-h-[100dvh]">
      <AppHeader />
      <main class="mx-auto max-w-6xl px-4 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Discover
        </h1>
        <p class="mt-2 text-muted">
          What is out, coming, and airing now. Add anything in one tap.
        </p>

        <Show when={problem()}>
          {(message) => <Alert class="mt-4">{message()}</Alert>}
        </Show>

        <DiscoverRows
          rows={rows()}
          onRowsChange={setRows}
          today={today()}
          onProblem={setProblem}
        />

        <footer class="mt-16 border-t border-line pt-6 text-sm text-muted">
          Lists from{' '}
          <a
            href={TMDB_URL}
            rel="noopener"
            class="font-medium text-accent hover:underline"
          >
            TMDB
          </a>
          ,{' '}
          <a
            href={ANILIST}
            rel="noopener"
            class="font-medium text-accent hover:underline"
          >
            AniList
          </a>{' '}
          and{' '}
          <a
            href={OPEN_LIBRARY}
            rel="noopener"
            class="font-medium text-accent hover:underline"
          >
            Open Library
          </a>
          .{' '}
          <Link
            to="/about"
            hash="credits"
            class="font-medium text-accent hover:underline"
          >
            Credits
          </Link>
        </footer>
      </main>
    </div>
  )
}
