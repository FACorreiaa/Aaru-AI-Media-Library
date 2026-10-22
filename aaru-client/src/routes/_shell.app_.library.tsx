import { Link, createFileRoute } from '@tanstack/solid-router'
import { useAppShell, useSearchHost } from '../components/shell/context'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import { optionalBoolean, optionalEnum } from '../lib/search-params'
import { AddToListDialog } from '../components/AddToListDialog'
import { Poster } from '../components/Poster'
import { Segmented } from '../components/Segmented'
import {
  Button,
  buttonVariants,
  Select,
  SelectContent,
  SelectItem,
  SelectPortal,
  SelectTrigger,
  SelectValue,
} from '~/components/ui'
import { NowSection } from '../components/library/NowSection'
import { lastShown } from '../lib/presence'
import {
  KINDS,
  shelf,
  statusLabel,
  statusOptions,
  upsert,
} from '../lib/library/model'
import type {
  LibraryEntry,
  LibraryStatus,
  MediaKind,
} from '../lib/library/model'
import { libraryQuery } from '../lib/queries'

// APP-003 on the web: the library, at parity with the Apple apps' `LibraryView`. `?search=true`
// opens Search on arrival; `?status=` and `?kind=` open it filtered (Home's count chips link
// there, and back or a reload keeps the filter, UX-088).
// Search loads only when it is first opened: it is not part of the page's first paint.

const STATUSES = ['wishlist', 'in_progress', 'finished', 'dropped'] as const
const KIND_VALUES = ['film', 'show', 'anime', 'book', 'album'] as const

export const Route = createFileRoute('/_shell/app_/library')({
  head: () => ({ meta: [{ title: 'Library · Aaru' }] }),
  validateSearch: (
    search,
  ): {
    search?: boolean
    status?: LibraryStatus
    kind?: MediaKind
  } => ({
    search: optionalBoolean(search.search),
    status: optionalEnum(search.status, STATUSES),
    kind: optionalEnum(search.kind, KIND_VALUES),
  }),
  loader: ({ context: { queryClient } }) => queryClient.query(libraryQuery),
  component: Library,
})

type Layout = 'grid' | 'rows'
type StatusChoice = { value: LibraryStatus | 'any'; label: string }

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
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const [entries, setEntries] = createSignal<LibraryEntry[]>(loaded())
  // Both filters live in the URL, so a link can open the library already filtered.
  const kind = () => search().kind ?? null
  const status = () => search().status ?? null
  function setFilters(next: {
    kind?: MediaKind | null
    status?: LibraryStatus | null
  }) {
    void navigate({
      search: (prev) => ({
        ...prev,
        ...('kind' in next ? { kind: next.kind ?? undefined } : {}),
        ...('status' in next ? { status: next.status ?? undefined } : {}),
      }),
      replace: true,
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
    if (search().search) {
      openSearch()
      // Back does not reopen it.
      void navigate({
        search: (prev) => ({ ...prev, search: undefined }),
        replace: true,
      })
    }
  })

  const rows = createMemo(() => shelf(entries(), kind(), status()))
  const statusChoices = createMemo<StatusChoice[]>(() => [
    { value: 'any', label: 'Any status' },
    ...statusOptions(kind()).map((s) => ({ value: s.status, label: s.label })),
  ])
  const statusChoice = () =>
    statusChoices().find((c) => c.value === (status() ?? 'any'))

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

        <NowSection
          entries={entries()}
          kind={kind()}
          onEntry={(entry) => setEntries((list) => upsert(list, entry))}
        />

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
          <Select<StatusChoice>
            aria-label="Status"
            options={statusChoices()}
            optionValue="value"
            optionTextValue="label"
            value={statusChoice()}
            disallowEmptySelection
            onChange={(choice) => {
              if (choice)
                setFilters({
                  status: choice.value === 'any' ? null : choice.value,
                })
            }}
            itemComponent={(p) => (
              <SelectItem item={p.item}>{p.item.rawValue.label}</SelectItem>
            )}
          >
            <SelectTrigger class="h-auto rounded-full border-line py-1.5 pr-3 pl-4 font-medium shadow-none">
              <SelectValue<StatusChoice>>
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
              { value: 'rows', label: 'Rows' },
            ]}
            value={layout()}
            onChange={chooseLayout}
          />
        </div>

        <Show
          when={rows().length > 0}
          fallback={
            <div class="mx-auto mt-24 max-w-sm text-center">
              <Show
                when={entries().length === 0}
                fallback={
                  <>
                    <h2 class="font-display text-2xl font-medium">
                      Nothing here
                    </h2>
                    <p class="mt-2 text-muted">
                      No titles match these filters.
                    </p>
                    <Button
                      variant="outline"
                      class="mt-6"
                      onClick={() => setFilters({ kind: null, status: null })}
                    >
                      Clear filters
                    </Button>
                  </>
                }
              >
                <h2 class="font-display text-2xl font-medium">
                  Your library is empty
                </h2>
                <p class="mt-2 text-muted">
                  Search for a film, show, anime, book or album, or bring your
                  history from another app.
                </p>
                <div class="mt-6 flex flex-wrap justify-center gap-3">
                  <Button variant="default" size="lg" onClick={openSearch}>
                    Search
                  </Button>
                  <Link
                    to="/app/settings/import"
                    class={buttonVariants({ variant: 'outline', size: 'lg' })}
                  >
                    Bring your history
                  </Link>
                </div>
              </Show>
            </div>
          }
        >
          <Show
            when={layout() === 'grid'}
            fallback={
              <ul class="mt-8 divide-y divide-line">
                <For each={rows()}>
                  {(row) => (
                    <li class="flex items-center gap-4">
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
                                  KINDS.find((k) => k.kind === row.kind)?.label,
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
                    </li>
                  )}
                </For>
              </ul>
            }
          >
            <ul class="mt-8 grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-x-4 gap-y-6">
              <For each={rows()}>
                {(row) => (
                  <li>
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
                        <p class="truncate text-xs text-muted">{row.byline}</p>
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
                  </li>
                )}
              </For>
            </ul>
          </Show>
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
