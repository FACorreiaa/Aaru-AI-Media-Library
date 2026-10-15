import {
  Link,
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onMount } from 'solid-js'
import { Wordmark } from '../components/Brand'
import { Poster } from '../components/Poster'
import { SearchPanel } from '../components/SearchPanel'
import { getLibrary } from '../lib/library/server'
import {
  KINDS,
  STATUSES,
  shelf,
  statusLabel,
  upsert,
} from '../lib/library/model'
import type {
  LibraryEntry,
  LibraryStatus,
  MediaKind,
} from '../lib/library/model'
import { getSession, signOut } from '../lib/session/session'

// APP-003 on the web: the shelf, at parity with the Apple apps' `LibraryView`.
export const Route = createFileRoute('/app')({
  head: () => ({ meta: [{ title: 'Library · Aaru' }] }),
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
  const router = useRouter()
  const navigate = useNavigate()
  const [entries, setEntries] = createSignal<LibraryEntry[]>(loaded())
  const [kind, setKind] = createSignal<MediaKind | null>(null)
  const [status, setStatus] = createSignal<LibraryStatus | null>(null)
  const [layout, setLayout] = createSignal<Layout>('grid')
  let dialog: HTMLDialogElement | undefined

  onMount(() => setLayout(readLayout()))

  const rows = createMemo(() => shelf(entries(), kind(), status()))

  function chooseLayout(next: Layout) {
    setLayout(next)
    try {
      localStorage.setItem('library.layout', next)
    } catch {
      // Private windows may refuse storage; the choice just does not stick.
    }
  }

  async function leave() {
    await signOut()
    await router.invalidate()
    await navigate({ to: '/' })
  }

  const chip = (on: boolean) =>
    on
      ? 'rounded-full bg-ink px-4 py-1.5 text-sm font-medium text-paper'
      : 'rounded-full border border-line px-4 py-1.5 text-sm font-medium text-ink hover:bg-surface'

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-6xl items-center justify-between gap-4 px-5 md:px-8">
        <Wordmark />
        <div class="flex items-center gap-5 text-sm font-medium">
          <Link to="/app/settings" class="text-muted hover:text-ink">
            Settings
          </Link>
          <Link to="/app/lists" class="text-muted hover:text-ink">
            Lists
          </Link>
          <button
            type="button"
            onClick={() => dialog?.showModal()}
            class="rounded-full bg-accent px-4 py-2 font-semibold text-on-accent active:scale-[0.98]"
          >
            Search
          </button>
          <button
            type="button"
            onClick={leave}
            class="text-muted hover:text-ink"
          >
            Sign out
          </button>
        </div>
      </header>

      <main class="mx-auto max-w-6xl px-5 pb-16 md:px-8">
        <h1 class="mt-4 font-display text-4xl font-medium tracking-tight">
          Library
        </h1>

        <div class="mt-6 flex flex-wrap items-center gap-2">
          <button
            type="button"
            class={chip(kind() === null)}
            onClick={() => setKind(null)}
          >
            All
          </button>
          <For each={KINDS}>
            {(option) => (
              <button
                type="button"
                class={chip(kind() === option.kind)}
                aria-pressed={kind() === option.kind}
                onClick={() => setKind(option.kind)}
              >
                {option.label}
              </button>
            )}
          </For>
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
            <For each={STATUSES}>
              {(s) => <option value={s.status}>{s.label}</option>}
            </For>
          </select>
          <div class="ml-auto flex overflow-hidden rounded-full border border-line text-sm">
            <button
              type="button"
              aria-pressed={layout() === 'grid'}
              class="px-3 py-1.5"
              classList={{ 'bg-surface font-semibold': layout() === 'grid' }}
              onClick={() => chooseLayout('grid')}
            >
              Grid
            </button>
            <button
              type="button"
              aria-pressed={layout() === 'list'}
              class="px-3 py-1.5"
              classList={{ 'bg-surface font-semibold': layout() === 'list' }}
              onClick={() => chooseLayout('list')}
            >
              List
            </button>
          </div>
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
                <button
                  type="button"
                  onClick={() => dialog?.showModal()}
                  class="mt-6 rounded-full bg-accent px-6 py-3 font-semibold text-on-accent"
                >
                  Search
                </button>
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
                    <li>
                      <Link
                        to="/app/title/$id"
                        params={{ id: row.id }}
                        class="flex items-center gap-4 py-3"
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
                            {[statusLabel(row.status), row.detail]
                              .filter(Boolean)
                              .join(' · ')}
                          </p>
                        </div>
                      </Link>
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
                        {row.detail ?? statusLabel(row.status)}
                      </p>
                    </Link>
                  </li>
                )}
              </For>
            </ul>
          </Show>
        </Show>
      </main>

      <dialog
        ref={dialog}
        aria-label="Search"
        class="m-auto w-[min(40rem,calc(100vw-2rem))] rounded-[20px] bg-paper p-0 text-ink shadow-2xl backdrop:bg-black/40"
        onClick={(e) => {
          // A click on the backdrop closes it.
          if (e.target === dialog) dialog.close()
        }}
      >
        <SearchPanel
          entries={entries()}
          onAdded={(entry) => setEntries(upsert(entries(), entry))}
          onClose={() => dialog?.close()}
        />
      </dialog>
    </div>
  )
}
