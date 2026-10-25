import { OwlEmpty } from '../components/Brand'
import { Link, createFileRoute } from '@tanstack/solid-router'
import { useAppShell, useSearchHost } from '../components/shell/context'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import {
  optionalBoolean,
  optionalEnum,
  optionalInt,
  optionalString,
} from '../lib/search-params'
import { FilterField, PageControls } from '../components/Paged'
import { clampPage, matches, pageOf } from '../lib/paging'
import { AddToListDialog } from '../components/AddToListDialog'
import { CardMenu } from '../components/CardMenu'
import { Poster } from '../components/Poster'
import { Segmented } from '../components/Segmented'
import { Button, buttonVariants } from '~/components/ui'
import { NowSection } from '../components/library/NowSection'
import { lastShown } from '../lib/presence'
import { prefersReducedMotion } from '../lib/reduced-motion'
import { KINDS, shelf, statusLabel, upsert } from '../lib/library/model'
import { statusTabs } from '../lib/library/tabs'
import type {
  LibraryEntry,
  LibraryStatus,
  MediaKind,
} from '../lib/library/model'
import { libraryQuery } from '../lib/queries'
import type { MarkTarget } from '../lib/title/model'

// APP-003 on the web: the library, at parity with the Apple apps' `LibraryView`. `?search=true`
// opens Search on arrival; `?status=` and `?kind=` open it filtered (Home's count chips link
// there, and back or a reload keeps the filter, UX-088). Every card has a menu (right-click, a
// long press, or its "⋯") to mark it watched or open it.
// Order (2026-10-22): the title, the filters, Now (capped, hidden while a status is chosen), then
// the shelf under a heading that names the filter. Arriving filtered scrolls to that heading.
// Search loads only when it is first opened: it is not part of the page's first paint.
// LIB-005: `?q=` filters every title in the library by name (original title and byline too),
// and the shelf shows 20 at a time with page numbers (`?page=`).
// LIB-007: the status is a strip of tabs with counts (All · Watching · Plan to watch · On hold ·
// Watched · Dropped, worded for the kind), still `?status=`, so Home's chips land on a tab.

const STATUSES = [
  'wishlist',
  'in_progress',
  'on_hold',
  'finished',
  'dropped',
] as const
const KIND_VALUES = ['film', 'show', 'anime', 'manga', 'book', 'album'] as const

export const Route = createFileRoute('/_shell/app_/library')({
  head: () => ({ meta: [{ title: 'Library · Aaru' }] }),
  validateSearch: (
    search,
  ): {
    search?: boolean
    status?: LibraryStatus
    kind?: MediaKind
    q?: string
    page?: number
  } => ({
    search: optionalBoolean(search.search),
    status: optionalEnum(search.status, STATUSES),
    kind: optionalEnum(search.kind, KIND_VALUES),
    q: optionalString(search.q),
    page: optionalInt(search.page, 1, 100_000),
  }),
  loader: ({ context: { queryClient } }) => queryClient.query(libraryQuery),
  component: Library,
})

type Layout = 'grid' | 'rows'
type StatusTabValue = LibraryStatus | 'all'

function readLayout(): Layout {
  try {
    // 'list' is what this was called before Grid / Rows (UX-048).
    const stored = localStorage.getItem('library.layout')
    return stored === 'rows' || stored === 'list' ? 'rows' : 'grid'
  } catch {
    return 'grid'
  }
}

function Library() {
  const loaded = Route.useLoaderData()
  const { queryClient } = Route.useRouteContext()()
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const [entries, setEntries] = createSignal<LibraryEntry[]>(loaded())
  // Both filters live in the URL, so a link can open the library already filtered.
  const kind = () => search().kind ?? null
  const status = () => search().status ?? null
  let shelfHeading: HTMLHeadingElement | undefined
  // The filter answers each keystroke from this signal; the URL follows so back and reload keep it.
  const [query, setQuery] = createSignal(search().q ?? '')
  function setFilters(next: {
    kind?: MediaKind | null
    status?: LibraryStatus | null
    q?: string
  }) {
    if ('q' in next) setQuery(next.q ?? '')
    void navigate({
      search: (prev) => ({
        ...prev,
        ...('kind' in next ? { kind: next.kind ?? undefined } : {}),
        ...('status' in next ? { status: next.status ?? undefined } : {}),
        ...('q' in next ? { q: next.q || undefined } : {}),
        // A new filter starts at its first page.
        page: undefined,
      }),
      replace: true,
    })
  }
  function setPage(page: number) {
    void navigate({ search: (prev) => ({ ...prev, page }), replace: true })
    shelfHeading?.scrollIntoView({
      block: 'start',
      behavior: prefersReducedMotion() ? 'auto' : 'smooth',
    })
  }
  const [layout, setLayout] = createSignal<Layout>('grid')
  // The entry whose "List…" was clicked: the picker adds its title to a list.
  const [listTarget, setListTarget] = createSignal<LibraryEntry | null>(null)
  const shownTarget = lastShown(listTarget)
  // UX-007: the shell's one Search, lent this page's library for its marks.
  const shell = useAppShell()
  useSearchHost({
    entries,
    onAdded: (entry) => setEntries(upsert(entries(), entry)),
  })
  function openSearch() {
    shell.openSearch()
  }

  function chooseList(libraryItemId: string) {
    setListTarget(entries().find((e) => e.id === libraryItemId) ?? null)
  }

  onMount(() => {
    setLayout(readLayout())
    // A link that opens the library filtered (Home's count chips) means the shelf, not Now.
    if ((search().status || search().kind) && shelfHeading) {
      const heading = shelfHeading
      requestAnimationFrame(() => {
        if (heading.getBoundingClientRect().top > window.innerHeight / 2)
          heading.scrollIntoView({
            block: 'start',
            behavior: prefersReducedMotion() ? 'auto' : 'smooth',
          })
      })
    }
    if (search().search) {
      openSearch()
      // Back does not reopen it.
      void navigate({
        search: (prev) => ({ ...prev, search: undefined }),
        replace: true,
      })
    }
  })

  const rows = createMemo(() =>
    shelf(entries(), kind(), status()).filter((row) =>
      matches(query(), row.title, row.originalTitle, row.byline),
    ),
  )
  const page = () => clampPage(search().page, rows().length)
  const shown = createMemo(() => pageOf(rows(), page()))
  const byId = createMemo(() => new Map(entries().map((e) => [e.id, e])))
  const targetOf = (id: string): MarkTarget => {
    const entry = byId().get(id)
    return {
      type: entry?.title.type ?? 'book',
      status: entry?.status,
      progress: entry?.progress,
    }
  }

  /** After a mark from a card's menu: its answer, or the library again after an undo. */
  async function changed(entry?: LibraryEntry) {
    if (entry) {
      setEntries((list) => upsert(list, entry))
      return
    }
    try {
      setEntries(await queryClient.query({ ...libraryQuery, staleTime: 0 }))
    } catch {
      // The undo landed; the shelf catches up on the next visit.
    }
  }

  /** "Shows · Watching", "Books", "Plan to watch", or "All titles". */
  const shelfTitle = () => {
    const parts = [
      KINDS.find((k) => k.kind === kind())?.label,
      status() ? statusLabel(status()!, kind()) : undefined,
    ].filter(Boolean)
    return parts.length > 0 ? parts.join(' · ') : 'All titles'
  }
  // Counted from the whole library this page already holds, so each tab agrees with the shelf it
  // opens, per kind, and follows a mark made here without another request.
  const tabs = createMemo(() => statusTabs(entries(), kind()))

  function chooseLayout(next: Layout) {
    setLayout(next)
    try {
      localStorage.setItem('library.layout', next)
    } catch {
      // Private windows may refuse storage; the choice just does not stick.
    }
  }

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <h1 class="font-display text-4xl font-medium tracking-tight">
          Library
        </h1>

        <div class="mt-6 flex flex-wrap items-center gap-2">
          <Segmented
            label="Kind"
            variant="chip"
            itemClass="px-4 py-1.5 text-sm"
            options={[
              { value: 'all', label: 'All' },
              ...KINDS.map((k) => ({ value: k.kind, label: k.label })),
            ]}
            value={kind() ?? 'all'}
            onChange={(next) =>
              setFilters({ kind: next === 'all' ? null : next })
            }
          />
          <FilterField
            label="Filter your library"
            placeholder="Filter your library"
            value={query()}
            onChange={(q) => setFilters({ q })}
            class="sm:ml-auto"
          />
          <Segmented
            label="Layout"
            options={[
              { value: 'grid', label: 'Grid' },
              { value: 'rows', label: 'Rows' },
            ]}
            value={layout()}
            onChange={chooseLayout}
          />
        </div>

        <Segmented<StatusTabValue>
          label="Status"
          variant="chip"
          class="mt-3"
          trackClass="flex-nowrap overflow-x-auto pb-1 [scrollbar-width:none]"
          itemClass="gap-1.5 px-4 py-1.5 text-sm"
          options={tabs().map((tab) => ({
            value: tab.status ?? 'all',
            label: (
              <>
                <span>{tab.label}</span>
                <span class="tabular-nums opacity-70">{tab.count}</span>
              </>
            ),
          }))}
          value={status() ?? 'all'}
          onChange={(next) =>
            setFilters({ status: next === 'all' ? null : next })
          }
        />

        {/* A chosen status or a filter is the shelf's own question; Now would only repeat part of it. */}
        <Show when={!status() && !query()}>
          <NowSection
            entries={entries()}
            kind={kind()}
            onEntry={(entry) => setEntries((list) => upsert(list, entry))}
          />
        </Show>

        <Show
          when={rows().length > 0}
          fallback={
            <div class="mt-12">
              <Show
                when={entries().length === 0}
                fallback={
                  <div class="mx-auto mt-12 max-w-sm text-center">
                    <h2 class="font-display text-2xl font-medium">
                      Nothing here
                    </h2>
                    <p class="mt-2 text-muted">
                      <Show
                        when={query()}
                        fallback="No titles match these filters."
                      >
                        No titles match “{query()}” here.
                      </Show>
                    </p>
                    <Button
                      variant="outline"
                      class="mt-6"
                      onClick={() =>
                        setFilters({ kind: null, status: null, q: '' })
                      }
                    >
                      Clear filters
                    </Button>
                  </div>
                }
              >
                <OwlEmpty
                  title="Your library is empty"
                  body="Search for a film, show, anime, book or album, or bring your history from another app."
                  action={
                    <div class="flex flex-wrap justify-center gap-3">
                      <Button variant="default" size="lg" onClick={openSearch}>
                        Search
                      </Button>
                      <Link
                        to="/app/settings/import"
                        class={buttonVariants({
                          variant: 'outline',
                          size: 'lg',
                        })}
                      >
                        Bring your history
                      </Link>
                    </div>
                  }
                />
              </Show>
            </div>
          }
        >
          <div class="mt-10 flex items-baseline justify-between gap-4">
            <h2
              ref={shelfHeading}
              class="scroll-mt-20 font-display text-2xl font-medium tracking-tight"
            >
              {shelfTitle()}
            </h2>
            <span class="text-sm text-muted">{rows().length}</span>
          </div>
          <Show
            when={layout() === 'grid'}
            fallback={
              <ul class="mt-3 divide-y divide-line">
                <For each={shown()}>
                  {(row) => (
                    <li>
                      <CardMenu
                        id={row.id}
                        name={row.title}
                        target={targetOf(row.id)}
                        onChanged={(entry) => void changed(entry)}
                        tone="row"
                        class="flex items-center gap-4"
                      >
                        <Link
                          to="/app/title/$id"
                          params={{ id: row.id }}
                          class="flex min-w-0 flex-1 items-center gap-4 py-3"
                        >
                          <Poster
                            url={row.posterUrl}
                            kind={row.kind}
                            class="w-12 shrink-0"
                          />
                          <div class="min-w-0">
                            <p class="line-clamp-2 font-medium">{row.title}</p>
                            <p class="truncate text-sm text-muted">
                              {(row.kind === 'album'
                                ? [row.byline, row.year]
                                : [
                                    row.year,
                                    KINDS.find((k) => k.kind === row.kind)
                                      ?.label,
                                  ]
                              )
                                .filter(Boolean)
                                .join(' · ')}
                            </p>
                            <p class="text-sm text-muted">
                              {[statusLabel(row.status, row.kind), row.detail]
                                .filter(Boolean)
                                .join(' · ')}
                            </p>
                          </div>
                        </Link>
                        <Button
                          variant="ghost"
                          size="sm"
                          class="shrink-0 text-muted hover:text-ink"
                          aria-label={`Add ${row.title} to a list`}
                          onClick={() => chooseList(row.id)}
                        >
                          List…
                        </Button>
                      </CardMenu>
                    </li>
                  )}
                </For>
              </ul>
            }
          >
            <ul class="mt-4 grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-x-4 gap-y-6">
              <For each={shown()}>
                {(row) => (
                  <li>
                    <CardMenu
                      id={row.id}
                      name={row.title}
                      target={targetOf(row.id)}
                      onChanged={(entry) => void changed(entry)}
                    >
                      <Link
                        to="/app/title/$id"
                        params={{ id: row.id }}
                        class="block"
                      >
                        {/* Among posters a square cover keeps their baseline; in the Music
 filter every cover is square and needs no slot. */}
                        <Poster
                          url={row.posterUrl}
                          kind={row.kind}
                          frame={kind() !== 'album'}
                        />
                        <p class="mt-2 line-clamp-2 text-sm font-medium">
                          {row.title}
                        </p>
                        <Show when={row.kind === 'album' && row.byline}>
                          <p class="truncate text-xs text-muted">
                            {row.byline}
                          </p>
                        </Show>
                        <p class="truncate text-xs text-muted">
                          {row.detail ?? statusLabel(row.status, row.kind)}
                        </p>
                      </Link>
                      <Button
                        variant="link"
                        size="bare"
                        class="mt-1 text-xs font-medium text-muted hover:text-ink"
                        aria-label={`Add ${row.title} to a list`}
                        onClick={() => chooseList(row.id)}
                      >
                        List…
                      </Button>
                    </CardMenu>
                  </li>
                )}
              </For>
            </ul>
          </Show>
          <PageControls
            page={page()}
            total={rows().length}
            label="Library pages"
            onPage={setPage}
          />
        </Show>
      </div>
      <Show when={shownTarget()}>
        {(entry) => (
          <AddToListDialog
            open={listTarget() !== null}
            mediaRef={{ titleId: entry().title.id, type: entry().title.type }}
            titleName={entry().title.title}
            onClose={() => setListTarget(null)}
          />
        )}
      </Show>
    </div>
  )
}
