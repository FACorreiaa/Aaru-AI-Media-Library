import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { Show, Suspense, createSignal, lazy, onMount } from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { DiscoverRows } from '../components/DiscoverRows'
import { Alert } from '../components/ui/alert'
import {
  SegmentedControl,
  SegmentedControlItem,
} from '../components/ui/segmented-control'
import { CREDITS, TMDB_URL } from '../lib/credits'
import { localDayKey } from '../lib/calendar/model'
import type { DiscoverRow } from '../lib/home/model'
import { getDiscover } from '../lib/home/server'
import { seasonOf } from '../lib/discover/season'
import type { SeasonKey, SeasonKind } from '../lib/discover/season'
import { optionalEnum, optionalInt } from '../lib/search-params'
import { getSession } from '../lib/session/session'

// The Seasons view loads on its own, the first time someone opens it.
const SeasonBrowser = lazy(() =>
  import('../components/SeasonBrowser').then((m) => ({
    default: m.SeasonBrowser,
  })),
)

// Discover on the web, the twin of the Apple apps' Discover tab: the same public rows Home
// shows under the user's own (DISC-001), on a page of their own, each card addable in place.
// The server names and orders the rows and marks the titles already on the shelf.
// `?view=seasons` is DISC-002's Seasons view: one season of anime, shows or films at a time.
export const Route = createFileRoute('/app_/discover')({
  head: () => ({ meta: [{ title: 'Discover · Aaru' }] }),
  validateSearch: (
    search,
  ): {
    view?: 'today' | 'seasons'
    kind?: SeasonKind
    season?: SeasonKey['season']
    year?: number
  } => ({
    view: optionalEnum(search.view, ['today', 'seasons']),
    kind: optionalEnum(search.kind, [
      'anime',
      'shows_new',
      'shows_returning',
      'movies',
    ]),
    season: optionalEnum(search.season, ['winter', 'spring', 'summer', 'fall']),
    year: optionalInt(search.year, 1970, 2200),
  }),
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
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const [rows, setRows] = createSignal<DiscoverRow[]>(loaded().rows)
  const [today, setToday] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(loaded().problem)

  // The release badges count days from the viewer's today, which only the browser knows.
  onMount(() => setToday(localDayKey(new Date())))

  const view = () => search().view ?? 'today'
  // Until the browser says, the server's day stands in: it only picks the default season.
  const day = () => today() ?? localDayKey(new Date())
  const season = (): SeasonKey => {
    const s = search()
    return s.season && s.year
      ? { season: s.season, year: s.year }
      : seasonOf(day())
  }
  const showSeason = (kind: SeasonKind, key: SeasonKey) =>
    void navigate({
      search: { view: 'seasons', kind, season: key.season, year: key.year },
      replace: true,
      resetScroll: false,
    })

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

        <SegmentedControl
          class="mt-6 flex w-fit overflow-hidden rounded-full border border-line text-sm"
          aria-label="Discover view"
          value={view()}
          onChange={(next) =>
            void navigate({
              search: next === 'seasons' ? { view: 'seasons' } : {},
              replace: true,
            })
          }
        >
          <SegmentedControlItem
            value="today"
            variant="surface"
            class="px-4 py-1.5"
          >
            Today
          </SegmentedControlItem>
          <SegmentedControlItem
            value="seasons"
            variant="surface"
            class="px-4 py-1.5"
          >
            Seasons
          </SegmentedControlItem>
        </SegmentedControl>

        <Show when={problem()}>
          {(message) => <Alert class="mt-4">{message()}</Alert>}
        </Show>

        <Show
          when={view() === 'seasons'}
          fallback={
            <DiscoverRows
              rows={rows()}
              onRowsChange={setRows}
              today={today()}
              onProblem={setProblem}
            />
          }
        >
          <Suspense>
            <SeasonBrowser
              kind={search().kind ?? 'anime'}
              season={season()}
              today={day()}
              onChange={showSeason}
              onProblem={setProblem}
            />
          </Suspense>
        </Show>

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
