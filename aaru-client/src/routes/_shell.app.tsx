import { Link, createFileRoute } from '@tanstack/solid-router'
import { useAppShell, useSearchHost } from '../components/shell/context'
import {
  For,
  Show,
  Suspense,
  createMemo,
  createSignal,
  lazy,
  onCleanup,
  onMount,
} from 'solid-js'
import { DiscoverRows } from '../components/DiscoverRows'
import { LastImportCard } from '../components/LastImportCard'
import { Medallion } from '../components/Medallion'
import { PlanCard } from '../components/PlanCard'
import { TonightStrip } from '../components/TonightStrip'
import {
  Alert,
  AlertDescription,
  Button,
  buttonVariants,
  cardClass,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import { WeekStripCard } from '../components/WeekStripCard'
import { ProgressStrip } from '../components/achievements/ProgressStrip'
import { PROGRESS_KEY } from '../lib/achievements/keys'
import type { Progress } from '../lib/achievements/model'
import {
  AiringCard,
  ContinueCard,
  ListeningCard,
  Row,
  StartCard,
  UnfinishedCard,
} from '../components/HomeRows'
import {
  addDays,
  fetchWindow,
  localDayKey,
  withWatched,
} from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import {
  AIRING_DAYS,
  advance,
  airingBadge,
  countChips,
  listening,
  markOnShelf,
  weekStrip,
  upcoming,
} from '../lib/home/model'
import type {
  ContinueEntry,
  DiscoverRow,
  UpNext,
  WeekStrip,
} from '../lib/home/model'
import { airingToday, composeTonight, fieldLine } from '../lib/home/tonight'
import { daypartHeading } from '../lib/appearance'
import type { ImportJob } from '../lib/imports/server'
import { upsert } from '../lib/library/model'
import type { LibraryEntry } from '../lib/library/model'
import {
  NOW_PLAYING_POLL_MS,
  libraryPlayEnded,
  playingLibraryItems,
} from '../lib/nowplaying/model'
import type { NowPlayingItem } from '../lib/nowplaying/model'
import { getNowPlaying } from '../lib/nowplaying/server'
import { useVisiblePoll } from '../lib/visible-poll'
import type { ListSummary } from '../lib/lists/server'
import { offeredRecap, periodLabel } from '../lib/recap/model'

import type { AgentPlan } from '../lib/plans/server'
import { flip, leave } from '../lib/motion'
import { setEpisode } from '../lib/title/server'
import {
  calendarQuery,
  discoverQuery,
  importsQuery,
  myStatsQuery,
  libraryQuery,
  listsQuery,
  pendingPlansQuery,
  progressQuery,
  upNextQuery,
} from '../lib/queries'
import type { QueryClient } from '@tanstack/solid-query'

// The Now playing card loads on its own the first time something plays. It is never in the
// first paint: Home asks what plays only once it has mounted.
const NowPlayingCard = lazy(() =>
  import('../components/NowPlayingCard').then((m) => ({
    default: m.NowPlayingCard,
  })),
)

// APP-009 on the web: Home, the twin of the Apple apps' first tab. Continue watching and Start
// watching come with the page; the calendar row loads in the browser, which knows the
// viewer's "today", as do this month's stats, Discover's public rows (DISC-001) and the list
// chips, so a cold provider cache never holds the page. Each of those hides itself if it
// fails. Search opens in place and shares the library for its "In your library" marks; the same
// library fills the Listening row (MUS-001), which stays hidden until it holds an album.
// Search loads only when it is first opened: it is not part of the page's first paint.
//
// The Field (DESIGN.md §1, "Mindspace", 2026-10-21): Tonight leads, the user's rows follow, and
// beside them on a wide screen sits the work happening in the room: requests waiting for the
// user, the last import, the week in numbers, lists. A phone stacks the same pieces, with
// requests right under Tonight.
//
// Now playing (SCR-008, SCR-009, DESIGN.md §15): everything Stremio, the browser extension,
// YouTube or a music scrobbler plays crosses the top of the Field, asked again every half minute
// while the tab is in view. Tonight and Continue watching leave every playing show out
// meanwhile, so none is on the page twice.

export const Route = createFileRoute('/_shell/app')({
  head: () => ({ meta: [{ title: 'Home · Aaru' }] }),
  loader: ({ context: { queryClient } }) => {
    // In the browser (a click, or a hover that preloads) the rest of the page starts with
    // Up next instead of after it mounts. On the first load the server cannot know the
    // viewer's day, so the page starts them when it mounts.
    if (typeof window !== 'undefined') startReads(queryClient, new Date())
    return queryClient.query(upNextQuery)
  },
  component: Home,
})

const viewerTimeZone = () =>
  Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'

const airingWindow = (today: string) =>
  fetchWindow(today, addDays(today, AIRING_DAYS - 1))

/** Every read Home shows besides Up next, all at once. Each row handles its own failure. */
function startReads(queryClient: QueryClient, current: Date) {
  const ignore = () => undefined
  const today = localDayKey(current)
  void queryClient.query(discoverQuery).catch(ignore)
  void queryClient.query(listsQuery).catch(ignore)
  void queryClient.query(pendingPlansQuery).catch(ignore)
  void queryClient.query(importsQuery).catch(ignore)
  void queryClient.query(libraryQuery).catch(ignore)
  void queryClient.query(progressQuery).catch(ignore)
  void queryClient
    .query(myStatsQuery({ span: 'last7', tz: viewerTimeZone() }))
    .catch(ignore)
  void queryClient.query(calendarQuery(airingWindow(today))).catch(ignore)
}

function Home() {
  const loaded = Route.useLoaderData()
  const context = Route.useRouteContext()
  const { queryClient } = context()
  const session = () => ({
    displayName: context().session.displayName,
    handle: context().session.handle,
  })
  /** Up next again, past the cache: after a write the rows must show it. */
  const freshUpNext = () => queryClient.query({ ...upNextQuery, staleTime: 0 })
  const [continuing, setContinuing] = createSignal(loaded().continueWatching)
  // UX-052: albums stay out of Start watching; in progress they have Listening.
  const withoutAlbums = <T extends { title: { type: string } }>(rows: T[]) =>
    rows.filter((row) => row.title.type !== 'album')
  const [starting, setStarting] = createSignal(
    withoutAlbums(loaded().startWatching),
  )
  const [unfinished, setUnfinished] = createSignal(loaded().unfinished ?? [])
  const [counts, setCounts] = createSignal(loaded().counts)
  const [strip, setStrip] = createSignal<WeekStrip | null>(null)
  const [lists, setLists] = createSignal<ListSummary[] | null>(null)
  const [airings, setAirings] = createSignal<CalendarEntry[]>([])
  const [now, setNow] = createSignal<Date | null>(null)
  const [airingsReady, setAiringsReady] = createSignal(false)
  const [busy, setBusy] = createSignal<ReadonlySet<string>>(new Set())
  const [problem, setProblem] = createSignal<string | null>(null)
  const [discover, setDiscover] = createSignal<DiscoverRow[]>([])
  const [discoverReady, setDiscoverReady] = createSignal(false)
  const [entries, setEntries] = createSignal<LibraryEntry[]>([])
  const [plans, setPlans] = createSignal<AgentPlan[]>([])
  const [lastImport, setLastImport] = createSignal<ImportJob | null>(null)
  const [progress, setProgress] = createSignal<Progress | null>(null)
  const [playing, setPlaying] = createSignal<NowPlayingItem[]>([])
  const [playingAt, setPlayingAt] = createSignal(new Date())
  /** Sessions marked watched here: the player may still report them for a while. */
  const [setAside, setSetAside] = createSignal<ReadonlySet<string>>(new Set())
  let libraryRequested = false

  // UX-007: the shell's one Search, lent this page's library for its marks.

  const shell = useAppShell()

  useSearchHost({ entries, onAdded: (entry) => void added(entry) })

  function openSearch() {
    shell.openSearch()
    loadLibrary()
  }

  function loadLibrary() {
    if (libraryRequested) return
    libraryRequested = true
    queryClient
      .query(libraryQuery)
      .then((library) => {
        // Anything added while it loaded is already on the server's answer, or kept here.
        setEntries((recent) => recent.reduce(upsert, library))
      })
      .catch(() => {
        // Adding still works; titles just lack their "In your library" mark. Try again later.
        libraryRequested = false
      })
  }

  function showUpNext(fresh: UpNext) {
    setContinuing(fresh.continueWatching)
    setStarting(withoutAlbums(fresh.startWatching))
    setUnfinished(fresh.unfinished ?? [])
    setCounts(fresh.counts)
  }

  /** A title added from Search or a Discover row: mark it in the library and refresh the rows. */
  async function added(entry: LibraryEntry) {
    setProblem(null)
    setEntries((current) => upsert(current, entry))
    setDiscover((rows) => markOnShelf(rows, entry))
    try {
      showUpNext(await freshUpNext())
    } catch {
      // The add landed; the rows catch up on the next visit.
    }
  }

  /** After a card's menu marked a title watched (or undid it): the rows and the library again. */
  function refreshRows(entry?: LibraryEntry) {
    if (entry) setEntries((current) => upsert(current, entry))
    void freshUpNext().then(showUpNext, () => {})
  }

  /** The last 7 days in numbers, in the viewer's time zone. A failure just leaves the strip
   * out. */
  async function loadStrip() {
    try {
      const stats = await queryClient.query(
        myStatsQuery({ span: 'last7', tz: viewerTimeZone() }),
      )
      setStrip(weekStrip(stats))
    } catch {
      setStrip(null)
    }
  }

  /** Agent requests waiting for the user (OUT-004), pinned above everything else. */
  async function loadPlans() {
    try {
      setPlans(await queryClient.query(pendingPlansQuery))
    } catch {
      // The requests stay on the server; the next visit shows them.
    }
  }

  /** The newest import, collapsed beside the rows. A failure just leaves it out. */
  async function loadLastImport() {
    try {
      const jobs = await queryClient.query(importsQuery)
      const newest = jobs.reduce<ImportJob | null>(
        (best, job) => (!best || job.createdAt > best.createdAt ? job : best),
        null,
      )
      setLastImport(newest)
    } catch {
      setLastImport(null)
    }
  }

  /** What players are playing now. When a library session ends (its stop may have ticked
   * the episode), the rows are fetched again so Continue watching moves on. */
  async function loadNowPlaying() {
    const before = playing()
    let fresh: NowPlayingItem[]
    try {
      fresh = await getNowPlaying()
    } catch {
      return
    }
    setPlaying(fresh)
    setPlayingAt(new Date())
    if (libraryPlayEnded(before, fresh))
      void freshUpNext().then(showUpNext, () => {})
  }

  useVisiblePoll(loadNowPlaying, NOW_PLAYING_POLL_MS)

  /** What the card shows: less any episode the user marked watched here. */
  const nowPlaying = createMemo(() =>
    playing().filter((item) => !setAside().has(item.id)),
  )
  const playingItems = createMemo(() => playingLibraryItems(nowPlaying()))

  /** Mark watched on the Now playing card: the same write as a tick anywhere else. */
  async function markPlayingWatched(current: NowPlayingItem) {
    const id = current.libraryItemId
    const episode = current.episode
    if (!id || !episode || busy().has(id)) return
    setBusyFor(id, true)
    setProblem(null)
    try {
      await setEpisode({
        data: {
          id,
          season: episode.season,
          episode: episode.number,
          watched: true,
        },
      })
      setSetAside((ids) => new Set(ids).add(current.id))
      showUpNext(await freshUpNext())
    } catch (err) {
      setProblem(
        err instanceof Error ? err.message : 'The episode was not marked.',
      )
    } finally {
      setBusyFor(id, false)
    }
  }

  async function loadDiscover() {
    try {
      setDiscover(await queryClient.query(discoverQuery))
    } catch {
      // Discover is extra: the user's own rows stand without it.
    } finally {
      setDiscoverReady(true)
    }
  }

  /** Level and streak (GAM-002/003). The unlock watcher refreshes the cache after a write; the
   * strip follows it. A failure just leaves the strip out. */
  async function loadProgress() {
    try {
      setProgress(await queryClient.query(progressQuery))
    } catch {
      setProgress(null)
    }
  }

  async function loadLists() {
    try {
      setLists(await queryClient.query(listsQuery))
    } catch {
      setLists(null)
    }
  }

  onMount(async () => {
    const current = new Date()
    setNow(current)
    const today = localDayKey(current)
    void loadStrip()
    void loadDiscover()
    void loadPlans()
    void loadLists()
    void loadLastImport()
    void loadNowPlaying()
    void loadProgress()
    const unsubscribe = queryClient.getQueryCache().subscribe((event) => {
      if (
        event.type === 'updated' &&
        event.action.type === 'success' &&
        event.query.queryKey[0] === PROGRESS_KEY[0]
      )
        setProgress(event.query.state.data as Progress)
    })
    onCleanup(unsubscribe)
    loadLibrary()
    try {
      setAirings(await queryClient.query(calendarQuery(airingWindow(today))))
    } catch (err) {
      setProblem(
        err instanceof Error
          ? err.message
          : 'The calendar could not be loaded.',
      )
    } finally {
      setAiringsReady(true)
    }
  })

  const nextAirings = createMemo(() => {
    const current = now()
    return current ? upcoming(airings(), current) : []
  })

  const recap = createMemo(() => {
    const current = now()
    return current ? offeredRecap(current) : null
  })

  const badgeFor = (entry: CalendarEntry) => {
    const current = now()
    return current ? airingBadge(entry, current) : null
  }

  // Continue watching alone needs no clock, so the server draws Tonight's lead too; today's
  // airings join in the browser.
  const tonight = createMemo(() => {
    const away = playingItems()
    return composeTonight(
      continuing().filter((e) => !away.has(e.libraryItemId)),
      airings().filter((a) => !away.has(a.libraryItemId)),
      now() ?? new Date(),
    )
  })
  /** The show Tonight leads with leaves Continue watching, so no card shows twice. */
  const tonightItem = () => {
    const pick = tonight()?.primary
    return pick?.kind === 'continue' ? pick.entry.libraryItemId : null
  }
  const continuingRow = createMemo(() =>
    continuing().filter(
      (e) =>
        e.libraryItemId !== tonightItem() &&
        !playingItems().has(e.libraryItemId),
    ),
  )
  const subline = createMemo(() => {
    const current = now()
    if (!current) return null
    return fieldLine(
      daypartHeading(current),
      counts()?.inProgress ?? 0,
      airingToday(airings(), current).length,
    )
  })

  const chips = createMemo(() => countChips(counts()))
  /** MUS-001: albums in progress, from the library Home already loads for Search. */
  const listeningNow = createMemo(() => listening(entries()))

  const empty = () =>
    continuing().length === 0 &&
    starting().length === 0 &&
    unfinished().length === 0 &&
    listeningNow().length === 0 &&
    airingsReady() &&
    nextAirings().length === 0

  function setBusyFor(id: string, on: boolean) {
    setBusy((current) => {
      const next = new Set(current)
      if (on) next.add(id)
      else next.delete(id)
      return next
    })
  }

  /** Marks the card's next episode watched: the card advances at once, the server's answer
   * then replaces the guess, and a failed write puts the card back where it was. */
  async function markWatched(entry: ContinueEntry, card?: HTMLElement) {
    const id = entry.libraryItemId
    if (busy().has(id)) return
    const index = continuing().findIndex((r) => r.libraryItemId === id)
    setBusyFor(id, true)
    setProblem(null)
    const step = () => setContinuing((rows) => advance(rows, entry))
    // The last episode takes the show off the row: it fades out, the cards after it slide in.
    // Tonight's card (no element) swaps to its next pick in place.
    const row = card?.parentElement
    if (card && entry.remainingCount <= 1 && row) {
      await leave(card)
      void flip(row, step)
    } else step()
    try {
      await setEpisode({
        data: {
          id,
          season: entry.next.season,
          episode: entry.next.number,
          watched: true,
        },
      })
    } catch (err) {
      setContinuing((rows) => {
        const rest = rows.filter((r) => r.libraryItemId !== id)
        rest.splice(Math.max(0, index), 0, entry)
        return rest
      })
      setProblem(
        err instanceof Error ? err.message : 'The episode was not marked.',
      )
      setBusyFor(id, false)
      return
    }
    const match = airings().find(
      (a) =>
        a.libraryItemId === id &&
        a.season === entry.next.season &&
        a.number === entry.next.number,
    )
    if (match) setAirings((rows) => withWatched(rows, match, true))
    try {
      showUpNext(await freshUpNext())
    } catch {
      // The write landed; the optimistic card stands until the next visit.
    } finally {
      setBusyFor(id, false)
    }
  }

  return (
    <div class="atmos flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <div class="mt-6 flex items-start justify-between gap-4">
          <h1 class="font-display text-4xl font-medium tracking-tight md:text-5xl">
            The Field
          </h1>
          {/* The way to the profile, as on the Apple apps' Home (owner, 2026-10-22). */}
          <Link
            to="/app/profile"
            aria-label="Your profile"
            class="shrink-0 rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            <Medallion person={session()} class="size-11 text-base" />
          </Link>
        </div>
        {/* Filled in the browser, which knows the viewer's day; the line is held open so
            nothing moves when it lands. */}
        <p class="mt-1 min-h-6 text-muted tabular-nums">{subline()}</p>

        <Show when={problem()}>
          {(message) => (
            <Alert variant="destructive" class="mt-4">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>

        <Show when={nowPlaying()[0]}>
          {(lead) => (
            <Suspense>
              <NowPlayingCard
                items={nowPlaying()}
                now={playingAt()}
                busy={busy().has(lead().libraryItemId ?? '')}
                onWatched={() => void markPlayingWatched(lead())}
              />
            </Suspense>
          )}
        </Show>

        <div class="flex flex-col lg:grid lg:grid-cols-[minmax(0,1fr)_20rem] lg:grid-rows-[auto_auto_1fr] lg:gap-x-10">
          <div class="order-1 lg:col-start-1 lg:row-start-1">
            <Show when={tonight()}>
              {(picked) => (
                <TonightStrip
                  tonight={picked()}
                  busy={
                    picked().primary.kind === 'continue' &&
                    busy().has(picked().primary.entry.libraryItemId)
                  }
                  onWatched={(entry) => void markWatched(entry)}
                />
              )}
            </Show>
            <Show when={strip()}>
              {(week) => <WeekStripCard week={week()} />}
            </Show>
          </div>

          {/* On a phone these join the column in order; on a wide screen they are the side
              column, held in view while the rows scroll. */}
          <div class="contents lg:sticky lg:top-6 lg:col-start-2 lg:row-span-3 lg:row-start-1 lg:mt-8 lg:flex lg:flex-col lg:gap-4 lg:self-start">
            <Show when={plans().length > 0}>
              <section
                class="order-2 mt-8 lg:mt-0"
                aria-labelledby="home-waiting"
              >
                <h2 id="home-waiting" class="eyebrow">
                  Waiting for you
                </h2>
                <div class="mt-3 grid gap-3 md:grid-cols-2 lg:grid-cols-1">
                  <For each={plans()}>
                    {(plan) => (
                      <PlanCard
                        plan={plan}
                        onDecided={(decided) => {
                          if (decided.status === 'applied')
                            void freshUpNext().then(showUpNext, () => {})
                        }}
                      />
                    )}
                  </For>
                </div>
              </section>
            </Show>
            <div class="order-4 mt-10 flex flex-col gap-4 lg:mt-0">
              <Show when={progress()}>
                {(current) => <ProgressStrip progress={current()} />}
              </Show>
              <Show when={lastImport()}>
                {(job) => <LastImportCard job={job()} />}
              </Show>
              <Show when={chips().length > 0}>
                <nav
                  aria-label="Your library by status"
                  class="flex flex-wrap gap-2"
                >
                  <For each={chips()}>
                    {(chip) => (
                      <Link
                        to="/app/library"
                        search={{ status: chip.status }}
                        class="rounded-full border border-line px-4 py-1.5 text-sm font-medium hover:bg-surface"
                      >
                        {chip.label}{' '}
                        <span class="text-muted tabular-nums">
                          {chip.count}
                        </span>
                      </Link>
                    )}
                  </For>
                </nav>
              </Show>

              <Show when={recap()}>
                {(period) => (
                  <Link
                    to="/app/recap"
                    search={period()}
                    class="rise flex items-center justify-between gap-4 rounded-card bg-ink p-5 text-paper"
                  >
                    <span>
                      <span class="block text-sm opacity-80">
                        Your recap is ready
                      </span>
                      <span class="font-display text-2xl font-medium">
                        {period().month
                          ? periodLabel(period())
                          : `${period().year} in Aaru`}
                      </span>
                    </span>
                    <span class="shrink-0 rounded-full bg-paper px-4 py-2 text-sm font-semibold text-ink">
                      Play
                    </span>
                  </Link>
                )}
              </Show>

              <Show when={lists()}>
                {(all) => (
                  <section aria-labelledby="home-lists">
                    <h2 id="home-lists" class="eyebrow">
                      Lists
                    </h2>
                    <div class="mt-3 flex flex-wrap gap-2">
                      <For each={all()}>
                        {(list) => (
                          <Link
                            to="/app/lists/$id"
                            params={{ id: list.id }}
                            class="rounded-full bg-surface px-4 py-2 text-sm font-medium hover:text-accent"
                          >
                            {list.name}{' '}
                            <span class="text-muted tabular-nums">
                              {list.itemCount}
                            </span>
                          </Link>
                        )}
                      </For>
                      <Link
                        to="/app/lists"
                        search={{ new: '1' }}
                        class="rounded-full border border-dashed border-line px-4 py-2 text-sm font-medium text-accent hover:bg-surface"
                      >
                        New list
                      </Link>
                    </div>
                  </section>
                )}
              </Show>
            </div>
          </div>

          <div class="order-3 min-w-0 lg:col-start-1 lg:row-start-2">
            <Show when={continuingRow().length > 0}>
              <Row title="Continue watching">
                <For each={continuingRow()}>
                  {(entry) => (
                    <ContinueCard
                      entry={entry}
                      busy={busy().has(entry.libraryItemId)}
                      onWatched={markWatched}
                      onChanged={refreshRows}
                    />
                  )}
                </For>
              </Row>
            </Show>

            <Show when={listeningNow().length > 0}>
              <Row title="Listening">
                <For each={listeningNow()}>
                  {(entry) => <ListeningCard entry={entry} />}
                </For>
              </Row>
            </Show>

            <Show when={nextAirings().length > 0}>
              <Row
                title="Coming up"
                action={
                  <Link
                    to="/app/calendar"
                    class="text-sm font-medium text-accent hover:underline"
                  >
                    See calendar
                  </Link>
                }
              >
                <For each={nextAirings()}>
                  {(entry) => (
                    <AiringCard
                      entry={entry}
                      when={badgeFor(entry)}
                      onChanged={refreshRows}
                    />
                  )}
                </For>
              </Row>
            </Show>

            <Show when={starting().length > 0}>
              <Row title="Start watching">
                <For each={starting()}>
                  {(entry) => (
                    <StartCard entry={entry} onChanged={refreshRows} />
                  )}
                </For>
              </Row>
            </Show>

            <Show when={unfinished().length > 0}>
              <Row title="Unfinished business">
                <For each={unfinished()}>
                  {(entry) => (
                    <UnfinishedCard
                      entry={entry}
                      now={now()}
                      onChanged={refreshRows}
                    />
                  )}
                </For>
              </Row>
            </Show>
          </div>

          <div class="order-5 min-w-0 lg:col-start-1 lg:row-start-3">
            <Show when={empty() && (!discoverReady() || discover().length > 0)}>
              <div
                class={cn(
                  cardClass,
                  'mt-8 flex flex-wrap items-center justify-between gap-4 p-5',
                )}
              >
                <div>
                  <h2 class="font-display text-xl font-medium">
                    Add something to see what’s next
                  </h2>
                  <p class="mt-1 text-sm text-muted">
                    Pick from the rows below, search, or bring your history from
                    another app. What you watch and what airs next land here.
                  </p>
                </div>
                <div class="flex flex-wrap items-center gap-2">
                  <Link
                    to="/app/settings/import"
                    class={buttonVariants({ variant: 'quiet', size: 'sm' })}
                  >
                    Bring your history
                  </Link>
                  <Button variant="default" size="sm" onClick={openSearch}>
                    Search
                  </Button>
                </div>
              </div>
            </Show>

            <DiscoverRows
              rows={discover()}
              onRowsChange={setDiscover}
              today={now() ? localDayKey(now() as Date) : null}
              onAdded={(entry) => void added(entry)}
              onProblem={setProblem}
            />

            <Show when={empty() && discoverReady() && discover().length === 0}>
              <div class="mx-auto mt-16 max-w-sm text-center">
                <h2 class="font-display text-2xl font-medium">
                  Add something to see what’s next
                </h2>
                <p class="mt-2 text-muted">
                  What you are watching, what you want to start, and what airs
                  this week land here.
                </p>
                <div class="mt-6 flex flex-wrap items-center justify-center gap-3">
                  <Button variant="default" size="lg" onClick={openSearch}>
                    Search
                  </Button>
                  <Link
                    to="/app/settings/import"
                    class={buttonVariants({ variant: 'quiet', size: 'lg' })}
                  >
                    Bring your history
                  </Link>
                </div>
              </div>
            </Show>
          </div>
        </div>
      </div>
    </div>
  )
}
