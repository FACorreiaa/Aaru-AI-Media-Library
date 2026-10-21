import { Link, createFileRoute } from '@tanstack/solid-router'
import {
  For,
  Show,
  Suspense,
  createMemo,
  createSignal,
  lazy,
  onMount,
} from 'solid-js'
import { AppHeader } from '../components/AppHeader'
import { DiscoverRows } from '../components/DiscoverRows'
import { LastImportCard } from '../components/LastImportCard'
import { PlanCard } from '../components/PlanCard'
import { TonightStrip } from '../components/TonightStrip'
import { Alert } from '../components/ui/alert'
import { Button, buttonVariants } from '../components/ui/button'
import { cardClass } from '../components/ui/card'
import { Dialog } from '../components/ui/dialog'
import { cn } from '../lib/cn'
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
import type { ListSummary } from '../lib/lists/server'
import { offeredRecap, periodLabel } from '../lib/recap/model'
import { requireSession } from '../lib/session/query'
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
  upNextQuery,
} from '../lib/queries'
import type { QueryClient } from '@tanstack/solid-query'

// APP-009 on the web: Home, the twin of the Apple apps' first tab. Continue watching and Start
// watching come with the page; the calendar row loads in the browser, which knows the
// viewer's "today", as do this month's stats, Discover's public rows (DISC-001) and the list
// chips, so a cold provider cache never holds the page. Each of those hides itself if it
// fails. Search opens in place and shares the library for its "On your shelf" marks; the same
// library fills the Listening row (MUS-001), which stays hidden until it holds an album.
// Search loads only when it is first opened: it is not part of the page's first paint.
//
// The Field (DESIGN.md §1, "Mindspace", 2026-10-21): Tonight leads, the user's rows follow, and
// beside them on a wide screen sits the work happening in the room: requests waiting for the
// user, the last import, the week in numbers, lists. A phone stacks the same pieces, with
// requests right under Tonight.
const SearchPanel = lazy(() =>
  import('../components/SearchPanel').then((m) => ({ default: m.SearchPanel })),
)

export const Route = createFileRoute('/app')({
  head: () => ({ meta: [{ title: 'Home · Aaru' }] }),
  beforeLoad: async ({ context }) => ({
    session: await requireSession(context.queryClient),
  }),
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
  void queryClient
    .query(myStatsQuery({ span: 'last7', tz: viewerTimeZone() }))
    .catch(ignore)
  void queryClient.query(calendarQuery(airingWindow(today))).catch(ignore)
}

function Home() {
  const loaded = Route.useLoaderData()
  const { queryClient } = Route.useRouteContext()()
  /** Up next again, past the cache: after a write the rows must show it. */
  const freshUpNext = () => queryClient.query({ ...upNextQuery, staleTime: 0 })
  const [continuing, setContinuing] = createSignal(loaded().continueWatching)
  const [starting, setStarting] = createSignal(loaded().startWatching)
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
  const [searchOpened, setSearchOpened] = createSignal(false)
  const [entries, setEntries] = createSignal<LibraryEntry[]>([])
  const [plans, setPlans] = createSignal<AgentPlan[]>([])
  const [lastImport, setLastImport] = createSignal<ImportJob | null>(null)
  let dialog: HTMLDialogElement | undefined
  let libraryRequested = false

  function openSearch() {
    setSearchOpened(true)
    dialog?.showModal()
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
        // Adding still works; titles just lack their "On your shelf" mark. Try again later.
        libraryRequested = false
      })
  }

  function showUpNext(fresh: UpNext) {
    setContinuing(fresh.continueWatching)
    setStarting(fresh.startWatching)
    setUnfinished(fresh.unfinished ?? [])
    setCounts(fresh.counts)
  }

  /** A title added from Search or a Discover row: mark it on the shelf and refresh the rows. */
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

  async function loadDiscover() {
    try {
      setDiscover(await queryClient.query(discoverQuery))
    } catch {
      // Discover is extra: the user's own rows stand without it.
    } finally {
      setDiscoverReady(true)
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
  const tonight = createMemo(() =>
    composeTonight(continuing(), airings(), now() ?? new Date()),
  )
  /** The show Tonight leads with leaves Continue watching, so no card shows twice. */
  const tonightItem = () => {
    const pick = tonight()?.primary
    return pick?.kind === 'continue' ? pick.entry.libraryItemId : null
  }
  const continuingRow = createMemo(() =>
    continuing().filter((e) => e.libraryItemId !== tonightItem()),
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
    <div class="atmos min-h-[100dvh]">
      <AppHeader onSearch={openSearch} />
      <main class="mx-auto max-w-6xl px-4 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight md:text-5xl">
          The Field
        </h1>
        {/* Filled in the browser, which knows the viewer's day; the line is held open so
            nothing moves when it lands. */}
        <p class="mt-1 min-h-6 text-muted tabular-nums">{subline()}</p>

        <Show when={problem()}>
          {(message) => <Alert class="mt-4">{message()}</Alert>}
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
              <Show when={lastImport()}>
                {(job) => <LastImportCard job={job()} />}
              </Show>
              <Show when={strip()}>
                {(week) => (
                  <Link
                    to="/app/insights"
                    search={{ span: 'last7' }}
                    class={cn(
                      cardClass,
                      'flex items-center gap-4 px-5 py-4 hover:text-accent',
                    )}
                  >
                    <span
                      class="flex h-8 w-20 shrink-0 items-end gap-[3px] text-accent"
                      aria-hidden="true"
                    >
                      <For each={week().days}>
                        {(height) => (
                          <span
                            class="flex-1 rounded-[2px]"
                            classList={{
                              'bg-current': height > 0,
                              'bg-line': height === 0,
                            }}
                            style={{
                              height:
                                height > 0
                                  ? `${Math.max(height * 100, 15)}%`
                                  : '3px',
                            }}
                          />
                        )}
                      </For>
                    </span>
                    <span class="min-w-0 flex-1">
                      <span class="block text-sm text-muted">Last 7 days</span>
                      {/* Each figure keeps its words together; lines break only between them. */}
                      <span class="font-medium tabular-nums">
                        <Show
                          when={week().parts.length > 0}
                          fallback="Nothing tracked yet"
                        >
                          <For each={week().parts}>
                            {(part, i) => (
                              <>
                                {i() > 0 && ' · '}
                                <span class="whitespace-nowrap">{part}</span>
                              </>
                            )}
                          </For>
                        </Show>
                      </span>
                    </span>
                    <span class="shrink-0 text-sm font-semibold text-accent">
                      Insights
                    </span>
                  </Link>
                )}
              </Show>

              <Show when={chips().length > 0}>
                <nav
                  aria-label="Your shelf by status"
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
                    to="/app/week"
                    class="text-sm font-medium text-accent hover:underline"
                  >
                    See calendar
                  </Link>
                }
              >
                <For each={nextAirings()}>
                  {(entry) => (
                    <AiringCard entry={entry} when={badgeFor(entry)} />
                  )}
                </For>
              </Row>
            </Show>

            <Show when={starting().length > 0}>
              <Row title="Start watching">
                <For each={starting()}>
                  {(entry) => <StartCard entry={entry} />}
                </For>
              </Row>
            </Show>

            <Show when={unfinished().length > 0}>
              <Row title="Unfinished business">
                <For each={unfinished()}>
                  {(entry) => <UnfinishedCard entry={entry} now={now()} />}
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
                    Add a show to see what’s next
                  </h2>
                  <p class="mt-1 text-sm text-muted">
                    Pick from the rows below, browse Discover, or search. What
                    you watch and what airs next land here.
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <Link
                    to="/app/discover"
                    class="rounded-full border border-line px-5 py-2 text-sm font-semibold hover:bg-paper"
                  >
                    Discover
                  </Link>
                  <button
                    type="button"
                    onClick={openSearch}
                    class="rounded-full bg-accent px-5 py-2 text-sm font-semibold text-on-accent"
                  >
                    Search
                  </button>
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
                  Add a show to see what’s next
                </h2>
                <p class="mt-2 text-muted">
                  Shows you are watching, what you want to start, and what airs
                  this week land here.
                </p>
                <div class="mt-6 flex items-center justify-center gap-3">
                  <Link
                    to="/app/discover"
                    class={buttonVariants({ variant: 'primary', size: 'lg' })}
                  >
                    Discover
                  </Link>
                  <Button variant="quiet" size="lg" onClick={openSearch}>
                    Search
                  </Button>
                </div>
              </div>
            </Show>
          </div>
        </div>
      </main>

      <Dialog
        ref={dialog}
        aria-label="Search"
        class="w-[min(40rem,calc(100vw-2rem))]"
      >
        <Show when={searchOpened()}>
          <Suspense
            fallback={
              <p class="px-5 py-8 text-center text-sm text-muted">Loading…</p>
            }
          >
            <SearchPanel
              entries={entries()}
              onAdded={(entry) => void added(entry)}
              onClose={() => dialog?.close()}
            />
          </Suspense>
        </Show>
      </Dialog>
    </div>
  )
}
