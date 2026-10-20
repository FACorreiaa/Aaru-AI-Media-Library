import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { DiscoverRow } from '../components/DiscoverRow'
import { CREDITS, TMDB_URL } from '../lib/credits'
import { localDayKey } from '../lib/calendar/model'
import { sectionTitle } from '../lib/discover/model'
import type { DiscoverSection } from '../lib/discover/model'
import { getDiscover } from '../lib/discover/server'
import { upsert } from '../lib/library/model'
import type { LibraryEntry } from '../lib/library/model'
import { getLibrary } from '../lib/library/server'
import { getSession } from '../lib/session/session'

// Discover on the web, the twin of the Apple apps' Discover tab: trending, coming to cinemas,
// new and airing shows, and this and next season's anime, each addable in place. The library
// comes along so cards already on the shelf say so.
export const Route = createFileRoute('/app_/discover')({
  head: () => ({ meta: [{ title: 'Discover · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
    return { session }
  },
  loader: async () => {
    const [discover, library] = await Promise.all([
      getDiscover({ data: {} }).then(
        (d) => ({ sections: d.sections, problem: null }),
        (err: unknown) => ({
          sections: [] as DiscoverSection[],
          problem:
            err instanceof Error
              ? err.message
              : 'Discover is not available right now.',
        }),
      ),
      getLibrary(),
    ])
    return { ...discover, library }
  },
  component: DiscoverPage,
})

const ANILIST = CREDITS.find((c) => c.name === 'AniList')?.href

function DiscoverPage() {
  const loaded = Route.useLoaderData()
  const [entries, setEntries] = createSignal<LibraryEntry[]>(loaded().library)
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
          {(message) => (
            <p
              role="alert"
              class="mt-4 rounded-[14px] bg-danger/10 px-4 py-3 text-sm text-danger"
            >
              {message()}
            </p>
          )}
        </Show>

        <For each={loaded().sections.filter((s) => s.items.length > 0)}>
          {(section) => (
            <DiscoverRow
              section={section.id}
              title={sectionTitle(section)}
              items={section.items}
              entries={entries()}
              today={today()}
              onAdded={(entry) => {
                setProblem(null)
                setEntries((current) => upsert(current, entry))
              }}
              onProblem={setProblem}
            />
          )}
        </For>

        <footer class="mt-16 border-t border-line pt-6 text-sm text-muted">
          Lists from{' '}
          <a
            href={TMDB_URL}
            rel="noopener"
            class="font-medium text-accent hover:underline"
          >
            TMDB
          </a>{' '}
          and{' '}
          <a
            href={ANILIST}
            rel="noopener"
            class="font-medium text-accent hover:underline"
          >
            AniList
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
