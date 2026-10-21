import { Link, createFileRoute } from '@tanstack/solid-router'
import {
  Match,
  Show,
  Suspense,
  Switch,
  createSignal,
  lazy,
  onMount,
} from 'solid-js'
import { DiscoverRows } from '../components/DiscoverRows'
import {
  Alert,
  AlertDescription,
  ToggleGroup,
  ToggleGroupItem,
} from '~/components/ui'
import { CREDITS, TMDB_URL } from '../lib/credits'
import { localDayKey } from '../lib/calendar/model'
import type { ConcertPlaceSetting } from '../lib/concerts/model'
import { parseView, shownView } from '../lib/concerts/view'
import type { DiscoverView } from '../lib/concerts/view'
import { getConcertPlace } from '../lib/concerts/server'
import type { DiscoverRow } from '../lib/home/model'
import { getDiscover } from '../lib/home/server'
import { seasonOf } from '../lib/discover/season'
import type { SeasonKey, SeasonKind } from '../lib/discover/season'
import { optionalEnum, optionalInt } from '../lib/search-params'

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
  loader: async () => {
    const [discover, concerts] = await Promise.all([
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
      // Concerts are an extra: without an answer the Concerts view stays hidden.
      getConcertPlace().catch((): ConcertPlaceSetting | null => null),
    ])
    return { ...discover, concerts }
  },
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

        <ToggleGroup
          class="mt-6 flex w-fit overflow-hidden rounded-full border border-line text-sm"
          aria-label="Discover view"
          value={view()}
          onChange={(next: string | null) =>
            next &&
            void navigate({
              search:
                next === 'seasons' || next === 'concerts' ? { view: next } : {},
              replace: true,
            })
          }
        >
          <ToggleGroupItem
            size="bare"
            value="today"
            variant="surface"
            class="px-4 py-1.5"
          >
            Today
          </ToggleGroupItem>
          <ToggleGroupItem
            size="bare"
            value="seasons"
            variant="surface"
            class="px-4 py-1.5"
          >
            Seasons
          </ToggleGroupItem>
          <Show when={concertsOn()}>
            <ToggleGroupItem
              size="bare"
              value="concerts"
              variant="surface"
              class="px-4 py-1.5"
            >
              Concerts
            </ToggleGroupItem>
          </Show>
        </ToggleGroup>

        <Show when={problem()}>
          {(message) => (
            <Alert variant="destructive" class="mt-4">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>

        <Switch
          fallback={
            <DiscoverRows
              rows={rows()}
              onRowsChange={setRows}
              today={today()}
              onProblem={setProblem}
            />
          }
        >
          <Match when={view() === 'seasons'}>
            <Suspense>
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
              <Suspense>
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
      </div>
    </div>
  )
}
