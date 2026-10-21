import { Link, createFileRoute, redirect } from '@tanstack/solid-router'
import {
  For,
  Show,
  Suspense,
  createMemo,
  createSignal,
  lazy,
  onMount,
} from 'solid-js'
import { optionalBoolean, optionalEnum } from '../lib/search-params'
import { AddToListDialog } from '../components/AddToListDialog'
import { AppHeader } from '../components/AppHeader'
import { Poster } from '../components/Poster'
import { Button } from '../components/ui/button'
import { Dialog } from '../components/ui/dialog'
import {
  SegmentedControl,
  SegmentedControlItem,
} from '../components/ui/segmented-control'
import { getLibrary } from '../lib/library/server'
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
import { getSession } from '../lib/session/session'

// APP-003 on the web: the shelf, at parity with the Apple apps' `LibraryView`. `?search=true`
// opens Search on arrival; `?status=` opens the shelf filtered to one status (Home's count
// chips link there).
// Search loads only when it is first opened: it is not part of the page's first paint.
const SearchPanel = lazy(() =>
  import('../components/SearchPanel').then((m) => ({ default: m.SearchPanel })),
)

export const Route = createFileRoute('/app_/library')({
  head: () => ({ meta: [{ title: 'Library · Aaru' }] }),
  validateSearch: (
    search,
  ): {
    search?: boolean
    status?: 'wishlist' | 'in_progress' | 'finished' | 'dropped'
  } => ({
    search: optionalBoolean(search.search),
    status: optionalEnum(search.status, [
      'wishlist',
      'in_progress',
      'finished',
      'dropped',
    ]),
  }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
    return { session }
  },
  loader: () => getLibrary(),
  component: Library,
})

type Layout = 'grid' | 'list'

function readLayout(): Layout {
  try {
    return localStorage.getItem('library.layout') === 'list' ? 'list' : 'grid'
  } catch {
    return 'grid'
  }
}

function Library() {
  const loaded = Route.useLoaderData()
  const search = Route.useSearch()
  const navigate = Route.useNavigate()
  const [entries, setEntries] = createSignal<LibraryEntry[]>(loaded())
  const [kind, setKind] = createSignal<MediaKind | null>(null)
  // The status filter lives in the URL, so a link can open the shelf already filtered.
  const status = () => search().status ?? null
  function setStatus(next: LibraryStatus | null) {
    void navigate({
      search: (prev) => ({ ...prev, status: next ?? undefined }),
      replace: true,
    })
  }
  const [layout, setLayout] = createSignal<Layout>('grid')
  // The entry whose "List…" was clicked: the picker adds its title to a list.
  const [listTarget, setListTarget] = createSignal<LibraryEntry | null>(null)
  let dialog: HTMLDialogElement | undefined
  // Search mounts on its first open and then stays, keeping its query between opens.
  const [searchOpened, setSearchOpened] = createSignal(false)
  function openSearch() {
    setSearchOpened(true)
    dialog?.showModal()
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

  function chooseLayout(next: Layout) {
    setLayout(next)
    try {
      localStorage.setItem('library.layout', next)
    } catch {
      // Private windows may refuse storage; the choice just does not stick.
    }
  }

  return (
    <div class="min-h-[100dvh]">
      <AppHeader onSearch={openSearch} />

      <main class="mx-auto max-w-6xl px-5 pb-16 md:px-8">
        <h1 class="mt-6 font-display text-4xl font-medium tracking-tight">
          Library
        </h1>

        <div class="mt-6 flex flex-wrap items-center gap-2">
          <SegmentedControl
            class="flex flex-wrap gap-2"
            aria-label="Kind"
            value={kind() ?? 'all'}
            onChange={(next) =>
              setKind(next === 'all' ? null : (next as MediaKind))
            }
          >
            <SegmentedControlItem
              value="all"
              variant="chip"
              class="px-4 py-1.5 text-sm"
            >
              All
            </SegmentedControlItem>
            <For each={KINDS}>
              {(option) => (
                <SegmentedControlItem
                  value={option.kind}
                  variant="chip"
                  class="px-4 py-1.5 text-sm"
                >
                  {option.label}
                </SegmentedControlItem>
              )}
            </For>
          </SegmentedControl>
          <label class="sr-only" for="status-filter">
            Status
          </label>
          <select
            id="status-filter"
            class="rounded-full border border-line bg-transparent py-1.5 pr-8 pl-4 text-sm font-medium text-ink focus:ring-2 focus:ring-accent"
            value={status() ?? ''}
            onChange={(e) =>
              setStatus((e.currentTarget.value || null) as LibraryStatus | null)
            }
          >
            <option value="">Any status</option>
            <For each={statusOptions(kind())}>
              {(s) => (
                // `selected` on the option: the select's value is applied before the
                // options exist.
                <option value={s.status} selected={s.status === status()}>
                  {s.label}
                </option>
              )}
            </For>
          </select>
          <SegmentedControl
            class="ml-auto flex overflow-hidden rounded-full border border-line text-sm"
            aria-label="Layout"
            value={layout()}
            onChange={(next) => chooseLayout(next as Layout)}
          >
            <SegmentedControlItem
              value="grid"
              variant="surface"
              class="px-3 py-1.5"
            >
              Grid
            </SegmentedControlItem>
            <SegmentedControlItem
              value="list"
              variant="surface"
              class="px-3 py-1.5"
            >
              List
            </SegmentedControlItem>
          </SegmentedControl>
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
                  </>
                }
              >
                <h2 class="font-display text-2xl font-medium">
                  Your shelf is empty
                </h2>
                <p class="mt-2 text-muted">
                  Search for a film, show, anime or book to start.
                </p>
                <Button
                  variant="primary"
                  size="lg"
                  onClick={openSearch}
                  class="mt-6"
                >
                  Search
                </Button>
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
                          <p class="text-sm text-muted">
                            {[
                              row.year,
                              KINDS.find((k) => k.kind === row.kind)?.label,
                            ]
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
                      <button
                        type="button"
                        class="shrink-0 text-sm font-medium text-muted hover:text-ink"
                        onClick={() => chooseList(row.id)}
                      >
                        List…
                      </button>
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
                      <Poster url={row.posterUrl} kind={row.kind} />
                      <p class="mt-2 line-clamp-2 text-sm font-medium">
                        {row.title}
                      </p>
                      <p class="truncate text-xs text-muted">
                        {row.detail ?? statusLabel(row.status, row.kind)}
                      </p>
                    </Link>
                    <button
                      type="button"
                      class="mt-1 text-xs font-medium text-muted hover:text-ink"
                      onClick={() => chooseList(row.id)}
                    >
                      List…
                    </button>
                  </li>
                )}
              </For>
            </ul>
          </Show>
        </Show>
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
              onAdded={(entry) => setEntries(upsert(entries(), entry))}
              onClose={() => dialog?.close()}
            />
          </Suspense>
        </Show>
      </Dialog>
      <Show when={listTarget()}>
        {(entry) => (
          <AddToListDialog
            mediaRef={{ titleId: entry().title.id, type: entry().title.type }}
            titleName={entry().title.title}
            onClose={() => setListTarget(null)}
          />
        )}
      </Show>
    </div>
  )
}
