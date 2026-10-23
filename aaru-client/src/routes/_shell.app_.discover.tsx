import { OwlEmpty } from '../components/Brand'
import { Link, createFileRoute, useRouter } from '@tanstack/solid-router'
import {
  For,
  Match,
  Show,
  Suspense,
  Switch,
  createSignal,
  lazy,
  onMount,
} from 'solid-js'
import { DiscoverRows } from '../components/DiscoverRows'
import { Alert, AlertDescription, Button, Skeleton } from '~/components/ui'
import { useAppShell } from '../components/shell/context'
import { CREDITS, TMDB_URL } from '../lib/credits'
import { localDayKey } from '../lib/calendar/model'
import type { ConcertPlaceSetting } from '../lib/concerts/model'
import { parseView, shownView } from '../lib/concerts/view'
import type { DiscoverView } from '../lib/concerts/view'
import type { DiscoverRow } from '../lib/home/model'
import { seasonOf } from '../lib/discover/season'
import type { SeasonKey, SeasonKind } from '../lib/discover/season'
import { optionalEnum, optionalInt } from '../lib/search-params'
import { Segmented } from '../components/Segmented'
import { concertPlaceQuery, discoverQuery } from '../lib/queries'

// The Seasons and Concerts views load on their own, the first time someone opens them.
const SeasonBrowser = lazy(() =>
  import('../components/SeasonBrowser').then((m) => ({
    default: m.SeasonBrowser,
  })),
)
const ConcertList = lazy(() =>
  import('../components/ConcertList').then((m) => ({
    default: m.ConcertList,
  })),
)

// Discover on the web, the twin of the Apple apps' Discover tab: the same public rows Home
// shows under the user's own (DISC-001), on a page of their own, each card addable in place.
// The server names and orders the rows and marks the titles already on the shelf.
// `?view=seasons` is DISC-002's Seasons view: one season of anime, shows or films at a time.
// `?view=concerts` is MUS-003's Concerts view, offered only where the server has concerts on.
export const Route = createFileRoute('/_shell/app_/discover')({
  head: () => ({ meta: [{ title: 'Discover · Aaru' }] }),
  validateSearch: (
    search,
  ): {
    view?: DiscoverView
    kind?: SeasonKind
    season?: SeasonKey['season']
    year?: number
  } => ({
    view: parseView(search.view),
    kind: optionalEnum(search.kind, [
      'anime',
      'shows_new',
      'shows_returning',
      'movies',
    ]),
    season: optionalEnum(search.season, ['winter', 'spring', 'summer', 'fall']),
    year: optionalInt(search.year, 1970, 2200),
  }),
  loader: async ({ context: { queryClient } }) => {
    const [discover, concerts] = await Promise.all([
      queryClient.query(discoverQuery).then(
        (rows) => ({ rows, problem: null }),
        (err: unknown) => ({
          rows: [] as DiscoverRow[],
          problem:
            err instanceof Error
              ? err.message
              : 'Discover is not available right now.',
        }),
      ),
      // Concerts are an extra: without an answer the Concerts view stays hidden.
      queryClient
        .query(concertPlaceQuery)
        .catch((): ConcertPlaceSetting | null => null),
    ])
    return { ...discover, concerts }
  },
  component: DiscoverPage,
})

const ANILIST = CREDITS.find((c) => c.name === 'AniList')?.href ?? ''
const OPEN_LIBRARY = CREDITS.find((c) => c.name === 'Open Library')?.href ?? ''

type Source = { name: string; href: string }
const TMDB: Source = { name: 'TMDB', href: TMDB_URL }

/** UX-048: the credit names the providers of the rows on screen. Concerts carry their own. */
function sourcesFor(
  view: DiscoverView,
  kind: SeasonKind | undefined,
): Source[] {
  if (view === 'concerts') return []
  if (view === 'seasons')
    return (kind ?? 'anime') === 'anime'
      ? [{ name: 'AniList', href: ANILIST }]
      : [TMDB]
  return [
    TMDB,
    { name: 'AniList', href: ANILIST },
    { name: 'Open Library', href: OPEN_LIBRARY },
  ]
}

/** Seasons and Concerts load their code on first view: a row-sized placeholder holds the page. */
function Placeholder() {
  return (
    <div class="mt-8 flex flex-col gap-4" aria-hidden="true">
      <Skeleton class="mx-auto h-14 w-48 rounded-panel" />
      <div class="grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-4">
        <For each={[0, 1, 2, 3, 4, 5]}>
          {() => <Skeleton class="aspect-[2/3] rounded-card" />}
        </For>
      </div>
    </div>
  )
}

function DiscoverPage() {
  const loaded = Route.useLoaderData()
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const router = useRouter()
  const shell = useAppShell()
  const [rows, setRows] = createSignal<DiscoverRow[]>(loaded().rows)
  const [today, setToday] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(loaded().problem)
  const [concerts, setConcerts] = createSignal<ConcertPlaceSetting | null>(
    loaded().concerts,
  )

  // The release badges count days from the viewer's today, which only the browser knows.
  onMount(() => setToday(localDayKey(new Date())))

  const concertsOn = () => concerts()?.available === true
  const view = () => shownView(search().view, concertsOn())
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
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Discover
        </h1>
        <p class="mt-2 text-muted">
          What is out, coming, and airing now. Add anything in one tap.
        </p>

        <Segmented
          label="Discover view"
          class="mt-6"
          itemClass="px-4 py-1.5 text-sm"
          options={[
            { value: 'today', label: 'Today' },
            { value: 'seasons', label: 'Seasons' },
            ...(concertsOn()
              ? [{ value: 'concerts' as const, label: 'Concerts' }]
              : []),
          ]}
          value={view()}
          onChange={(next) =>
            void navigate({
              search: next === 'today' ? {} : { view: next },
              replace: true,
            })
          }
        />

        <Show when={problem()}>
          {(message) => (
            <Alert variant="destructive" class="mt-4">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>

        <Switch
          fallback={
            <Show
              when={rows().some((row) => row.items.length > 0)}
              fallback={
                <OwlEmpty
                  class="mt-12"
                  title="Nothing to discover right now"
                  body="The catalog lists could not be loaded. Search still works."
                  action={
                    <div class="flex flex-wrap justify-center gap-3">
                      <Button onClick={() => void router.invalidate()}>
                        Try again
                      </Button>
                      <Button
                        variant="quiet"
                        onClick={() => shell.openSearch()}
                      >
                        Search
                      </Button>
                    </div>
                  }
                />
              }
            >
              <DiscoverRows
                rows={rows()}
                onRowsChange={setRows}
                today={today()}
                onProblem={setProblem}
              />
            </Show>
          }
        >
          <Match when={view() === 'seasons'}>
            <Suspense fallback={<Placeholder />}>
              <SeasonBrowser
                kind={search().kind ?? 'anime'}
                season={season()}
                today={day()}
                onChange={showSeason}
                onProblem={setProblem}
              />
            </Suspense>
          </Match>
          <Match when={view() === 'concerts' && concerts()}>
            {(setting) => (
              <Suspense fallback={<Placeholder />}>
                <ConcertList
                  setting={setting()}
                  today={day()}
                  onSettingChange={setConcerts}
                />
              </Suspense>
            )}
          </Match>
        </Switch>

        <footer class="mt-16 border-t border-line pt-6 text-sm text-muted">
          <Show when={sourcesFor(view(), search().kind).length > 0}>
            Rows from{' '}
            <For each={sourcesFor(view(), search().kind)}>
              {(source, i) => (
                <>
                  {i() > 0 &&
                    (i() === sourcesFor(view(), search().kind).length - 1
                      ? ' and '
                      : ', ')}
                  <a
                    href={source.href}
                    rel="noopener"
                    class="font-medium text-accent hover:underline"
                  >
                    {source.name}
                  </a>
                </>
              )}
            </For>
            .{' '}
          </Show>
          <Link
            to="/about"
            hash="credits"
            class="font-medium text-accent hover:underline"
          >
            Credits
          </Link>
        </footer>
      </div>
    </div>
  )
}
