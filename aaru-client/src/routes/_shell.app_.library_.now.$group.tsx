import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { OwlEmpty } from '../components/Brand'
import { Segmented } from '../components/Segmented'
import { NowCard } from '../components/library/NowCard'
import { NowRow } from '../components/library/NowRow'
import { createNowWrites } from '../components/library/nowWrites'
import {
  Alert,
  AlertDescription,
  Button,
  Select,
  SelectContent,
  SelectItem,
  SelectPortal,
  SelectTrigger,
  SelectValue,
} from '~/components/ui'
import { KINDS, upsert } from '../lib/library/model'
import type { LibraryEntry, MediaKind } from '../lib/library/model'
import { GROUP_KINDS, groupTitle, isNowGroup } from '../lib/library/now-groups'
import { groupItems, sortNow } from '../lib/library/now'
import { watchingLines } from '../lib/library/watching'
import type {
  NowGroup,
  NowItem,
  NowSort,
  WatchingItem,
} from '../lib/library/now'
import { optionalEnum } from '../lib/search-params'
import { libraryQuery, watchingQuery } from '../lib/queries'

// APP-018: one Now group on its own page, reached from Library's "Show all". Every title in
// progress, as big cards (Grid) or dense rows (List), sorted by the last tick, the next airing
// (Watching) or A–Z, and narrowed by kind. Watching carries each show's facts from
// `GET /v1/library/watching`; anime the user never touched in Aaru sit apart, collapsed, in the
// Anime backlog (`#backlog` opens it). Reading and Listening need nothing past the library.

const SORTS = ['recent', 'airs', 'title'] as const
const KIND_VALUES = ['film', 'show', 'anime', 'manga', 'book', 'album'] as const

type Layout = 'grid' | 'list'
type SortChoice = { value: NowSort; label: string }

export const Route = createFileRoute('/_shell/app_/library_/now/$group')({
  validateSearch: (search): { kind?: MediaKind; sort?: NowSort } => ({
    kind: optionalEnum(search.kind, KIND_VALUES),
    sort: optionalEnum(search.sort, SORTS),
  }),
  loader: async ({ params, context: { queryClient } }) => {
    if (!isNowGroup(params.group))
      throw redirect({ to: '/app/library', replace: true })
    const [entries, watching] = await Promise.all([
      queryClient.query(libraryQuery),
      params.group === 'watching'
        ? queryClient.query(watchingQuery)
        : Promise.resolve([] as WatchingItem[]),
    ])
    return { entries, watching }
  },
  component: NowGroupPage,
  head: ({ params }) => ({
    meta: [
      {
        title: `${isNowGroup(params.group) ? groupTitle(params.group) : 'Library'} · Aaru`,
      },
    ],
  }),
})

function readLayout(): Layout {
  try {
    return localStorage.getItem('library.now.layout') === 'list'
      ? 'list'
      : 'grid'
  } catch {
    return 'grid'
  }
}

function NowGroupPage() {
  const params = Route.useParams()
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const loaded = Route.useLoaderData()
  const { queryClient } = Route.useRouteContext()()
  const group = () => params().group as NowGroup
  const isWatching = () => group() === 'watching'

  const [entries, setEntries] = createSignal<LibraryEntry[]>(loaded().entries)
  const [watching, setWatching] = createSignal<WatchingItem[]>(
    loaded().watching,
  )
  const byId = createMemo(
    () => new Map(watching().map((item) => [item.entry.id, item])),
  )
  const [layout, setLayout] = createSignal<Layout>('grid')
  const [backlogOpen, setBacklogOpen] = createSignal(false)
  // Relative airing words ("Tomorrow") need the viewer's clock: none until the browser runs.
  const [now, setNow] = createSignal<Date | null>(null)
  let backlogHeading: HTMLHeadingElement | undefined
  onMount(() => {
    setLayout(readLayout())
    setNow(new Date())
    if (location.hash === '#backlog') {
      setBacklogOpen(true)
      requestAnimationFrame(() => backlogHeading?.scrollIntoView())
    }
  })

  const kinds = () => GROUP_KINDS[group()]
  const kind = () => {
    const chosen = search().kind
    return chosen && kinds().includes(chosen) ? chosen : null
  }
  const sort = (): NowSort => {
    const chosen = search().sort ?? 'recent'
    return chosen === 'airs' && !isWatching() ? 'recent' : chosen
  }
  function setSearch(next: { kind?: MediaKind | null; sort?: NowSort }) {
    void navigate({
      search: (prev) => ({
        ...prev,
        ...('kind' in next ? { kind: next.kind ?? undefined } : {}),
        ...('sort' in next
          ? { sort: next.sort === 'recent' ? undefined : next.sort }
          : {}),
      }),
      replace: true,
    })
  }
  function chooseLayout(next: Layout) {
    setLayout(next)
    try {
      localStorage.setItem('library.now.layout', next)
    } catch {
      // Private windows may refuse storage; the choice just does not stick.
    }
  }

  const page = createMemo(() => groupItems(entries(), group(), kind()))
  const airsAt = (item: NowItem) =>
    byId().get(item.entry.id)?.nextAiring?.airsAt
  const active = createMemo(() => sortNow(page().active, sort(), airsAt))
  // The backlog is long and untouched: A–Z unless another order is chosen.
  const backlog = createMemo(() =>
    sortNow(page().backlog, sort() === 'recent' ? 'title' : sort(), airsAt),
  )

  const sortChoices = createMemo<SortChoice[]>(() => [
    { value: 'recent', label: isWatching() ? 'Recently watched' : 'Recent' },
    ...(isWatching() ? [{ value: 'airs' as const, label: 'Airs next' }] : []),
    { value: 'title', label: 'A–Z' },
  ])

  /** The facts under a title: Watching's from the server, a book's or album's byline. */
  function lines(item: NowItem): string[] {
    if (isWatching()) {
      const facts = byId().get(item.entry.id)
      const clock = now()
      return watchingLines(
        item,
        facts && !clock ? { ...facts, nextAiring: undefined } : facts,
        clock ?? new Date(0),
      )
    }
    return [item.entry.title.byline].filter((line): line is string => !!line)
  }

  async function changed(entry: LibraryEntry) {
    setEntries((list) => upsert(list, entry))
    if (!isWatching()) return
    try {
      setWatching(await queryClient.query({ ...watchingQuery, staleTime: 0 }))
    } catch {
      // The entry already moved; the facts catch up on the next visit.
    }
  }
  const writes = createNowWrites((entry) => void changed(entry))

  const Items = (props: { items: NowItem[] }): JSX.Element => (
    <Show
      when={layout() === 'grid'}
      fallback={
        <ul class="mt-3 divide-y divide-line">
          <For each={props.items}>
            {(item) => (
              <NowRow
                item={item}
                pending={writes.isPending(item)}
                lines={lines(item)}
                {...writes.actions(item)}
              />
            )}
          </For>
        </ul>
      }
    >
      <ul class="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <For each={props.items}>
          {(item) => (
            <NowCard
              item={item}
              pending={writes.isPending(item)}
              lines={lines(item)}
              {...writes.actions(item)}
            />
          )}
        </For>
      </ul>
    </Show>
  )

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <Link
          to="/app/library"
          search={{ kind: kind() ?? undefined }}
          class="text-sm text-muted hover:text-ink"
        >
          ‹ Library
        </Link>
        <div class="mt-2 flex items-baseline gap-3">
          <h1 class="font-display text-4xl font-medium tracking-tight">
            {groupTitle(group())}
          </h1>
          <span class="text-muted tabular-nums">{active().length}</span>
        </div>

        <div class="mt-6 flex flex-wrap items-center gap-2">
          <Show when={kinds().length > 1}>
            <Segmented
              label="Kind"
              variant="chip"
              itemClass="px-4 py-1.5 text-sm"
              options={[
                { value: 'all', label: 'All' },
                ...KINDS.filter((k) => kinds().includes(k.kind)).map((k) => ({
                  value: k.kind,
                  label: k.label,
                })),
              ]}
              value={kind() ?? 'all'}
              onChange={(next) =>
                setSearch({ kind: next === 'all' ? null : next })
              }
            />
          </Show>
          <Select<SortChoice>
            aria-label="Sort"
            options={sortChoices()}
            optionValue="value"
            optionTextValue="label"
            value={sortChoices().find((c) => c.value === sort())}
            disallowEmptySelection
            onChange={(choice) => {
              if (choice) setSearch({ sort: choice.value })
            }}
            itemComponent={(p) => (
              <SelectItem item={p.item}>{p.item.rawValue.label}</SelectItem>
            )}
          >
            <SelectTrigger class="h-auto rounded-full border-line py-1.5 pr-3 pl-4 font-medium shadow-none">
              <SelectValue<SortChoice>>
                {(state) => state.selectedOption().label}
              </SelectValue>
            </SelectTrigger>
            <SelectPortal>
              <SelectContent class="rounded-panel border-line bg-paper" />
            </SelectPortal>
          </Select>
          <Segmented
            class="ml-auto"
            label="Layout"
            options={[
              { value: 'grid', label: 'Grid' },
              { value: 'list', label: 'List' },
            ]}
            value={layout()}
            onChange={chooseLayout}
          />
        </div>

        <Show when={writes.problem()}>
          {(message) => (
            <Alert variant="destructive" class="mt-6">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>

        <Show
          when={active().length > 0 || backlog().length > 0}
          fallback={
            <div class="mt-12">
              <OwlEmpty
                title={`Nothing ${groupTitle(group()).toLowerCase()} right now`}
                body="Titles you are in the middle of show up here."
                action={
                  <Link
                    to="/app/library"
                    class="text-sm font-medium text-accent hover:underline"
                  >
                    Back to Library
                  </Link>
                }
              />
            </div>
          }
        >
          <Show when={active().length > 0}>
            <section aria-labelledby="now-keeping-up" class="mt-8">
              <Show when={backlog().length > 0}>
                <h2
                  id="now-keeping-up"
                  class="font-display text-2xl font-medium tracking-tight"
                >
                  Keeping up
                </h2>
              </Show>
              <Items items={active()} />
            </section>
          </Show>

          <Show when={backlog().length > 0}>
            <section aria-labelledby="backlog" class="mt-10">
              <div class="flex items-baseline justify-between gap-4">
                <h2
                  id="backlog"
                  ref={backlogHeading}
                  class="scroll-mt-20 font-display text-2xl font-medium tracking-tight"
                >
                  Anime backlog
                </h2>
                <Button
                  variant="link"
                  size="bare"
                  class="text-sm font-medium"
                  aria-expanded={backlogOpen()}
                  aria-controls="backlog-items"
                  onClick={() => setBacklogOpen(!backlogOpen())}
                >
                  {backlogOpen() ? 'Hide' : `Show ${backlog().length}`}
                </Button>
              </div>
              <p class="mt-1 text-sm text-muted">
                Anime that came in as watching from an import and that you have
                not started here. They stay in progress; tick an episode to
                bring one up.
              </p>
              <div id="backlog-items">
                <Show when={backlogOpen()}>
                  <Items items={backlog()} />
                </Show>
              </div>
            </section>
          </Show>
        </Show>
      </div>
    </div>
  )
}
