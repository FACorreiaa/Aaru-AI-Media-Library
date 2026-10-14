import { For, Show, createEffect, createSignal, onCleanup } from 'solid-js'
import { addToLibrary, searchCatalog } from '../lib/library/server'
import {
  KINDS,
  STATUSES,
  idKeys,
  isOnShelf,
  kindOf,
} from '../lib/library/model'
import type {
  CatalogHit,
  LibraryEntry,
  LibraryStatus,
  MediaKind,
} from '../lib/library/model'
import { Poster } from './Poster'

/** APP-004 on the web: type-scoped search, debounced, with add and an initial status. */
export function SearchPanel(props: {
  entries: LibraryEntry[]
  onAdded: (entry: LibraryEntry) => void
  onClose: () => void
}) {
  const [query, setQuery] = createSignal('')
  const [kind, setKind] = createSignal<MediaKind>('film')
  const [hits, setHits] = createSignal<CatalogHit[]>([])
  const [searching, setSearching] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  // Hits being added right now: a second click waits instead of adding twice.
  const [adding, setAdding] = createSignal<Set<string>>(new Set())
  let latest = 0

  createEffect(() => {
    const text = query().trim()
    const scope = KINDS.find((k) => k.kind === kind())?.search ?? 'movie'
    const ticket = ++latest
    if (text.length < 2) {
      setHits([])
      setProblem(null)
      return
    }
    // Debounce: a new keystroke replaces this timer before the request goes out.
    const timer = setTimeout(async () => {
      setSearching(true)
      try {
        const results = await searchCatalog({ data: { q: text, type: scope } })
        if (ticket === latest) {
          setHits(results)
          setProblem(null)
        }
      } catch (error) {
        if (ticket === latest) {
          setHits([])
          setProblem(error instanceof Error ? error.message : 'Search failed.')
        }
      } finally {
        if (ticket === latest) setSearching(false)
      }
    }, 300)
    onCleanup(() => clearTimeout(timer))
  })

  const keyOf = (hit: CatalogHit) =>
    idKeys(hit.ids).sort()[0] ?? `${hit.title}-${hit.year ?? ''}`

  async function add(hit: CatalogHit, status: LibraryStatus) {
    const key = keyOf(hit)
    if (adding().has(key)) return
    setAdding(new Set([...adding(), key]))
    try {
      const entry = await addToLibrary({
        data: {
          type: hit.type,
          ids: hit.ids,
          title: hit.title,
          year: hit.year,
          status,
        },
      })
      props.onAdded(entry)
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : `${hit.title} could not be added.`,
      )
    } finally {
      const next = new Set(adding())
      next.delete(key)
      setAdding(next)
    }
  }

  return (
    <div class="flex max-h-[85dvh] w-full flex-col">
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 class="font-display text-2xl font-medium">Search</h2>
        <button
          type="button"
          onClick={() => props.onClose()}
          class="text-sm font-medium text-muted hover:text-ink"
        >
          Done
        </button>
      </div>
      <div class="flex flex-col gap-3 px-5 pt-4">
        <label for="search" class="sr-only">
          Search
        </label>
        <input
          id="search"
          type="search"
          autofocus
          autocomplete="off"
          placeholder={kind() === 'book' ? 'Title, author or ISBN' : 'Title'}
          value={query()}
          onInput={(e) => setQuery(e.currentTarget.value)}
          class="min-h-12 w-full rounded-[14px] border-0 bg-surface px-4 text-base text-ink placeholder:text-muted/70 focus:ring-2 focus:ring-accent focus:outline-none"
        />
        <div class="flex gap-2" role="tablist" aria-label="Type">
          <For each={KINDS}>
            {(option) => (
              <button
                type="button"
                role="tab"
                aria-selected={kind() === option.kind}
                onClick={() => setKind(option.kind)}
                class="rounded-full px-4 py-1.5 text-sm font-medium transition-colors"
                classList={{
                  'bg-ink text-paper': kind() === option.kind,
                  'border border-line text-ink hover:bg-surface':
                    kind() !== option.kind,
                }}
              >
                {option.label}
              </button>
            )}
          </For>
        </div>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
      </div>
      <ul class="mt-3 flex-1 overflow-y-auto px-5 pb-5">
        <Show when={searching() && hits().length === 0}>
          <li class="py-8 text-center text-sm text-muted">Searching…</li>
        </Show>
        <Show
          when={
            !searching() &&
            !problem() &&
            query().trim().length >= 2 &&
            hits().length === 0
          }
        >
          <li class="py-8 text-center text-sm text-muted">
            No results for "{query().trim()}"
          </li>
        </Show>
        <For each={hits()}>
          {(hit) => {
            const kindOfHit = kindOf(hit.type, hit.isAnime)
            return (
              <li class="flex items-center gap-4 border-b border-line py-3 last:border-0">
                <Poster
                  url={hit.posterUrl}
                  kind={kindOfHit}
                  class="w-12 shrink-0"
                />
                <div class="min-w-0 flex-1">
                  <p class="line-clamp-2 font-medium">{hit.title}</p>
                  <p class="truncate text-sm text-muted">
                    {[hit.year, hit.byline].filter(Boolean).join(' · ')}
                  </p>
                </div>
                <Show
                  when={!isOnShelf(hit, props.entries)}
                  fallback={
                    <span class="text-sm font-medium text-accent">
                      On your shelf
                    </span>
                  }
                >
                  <Show
                    when={!adding().has(keyOf(hit))}
                    fallback={<span class="text-sm text-muted">Adding…</span>}
                  >
                    <div class="flex items-center overflow-hidden rounded-full border border-ink/25">
                      <button
                        type="button"
                        class="px-4 py-1.5 text-sm font-semibold hover:bg-surface"
                        onClick={() => add(hit, 'wishlist')}
                      >
                        Add
                      </button>
                      <label class="sr-only" for={`status-${keyOf(hit)}`}>
                        Add with status
                      </label>
                      <select
                        id={`status-${keyOf(hit)}`}
                        class="border-0 border-l border-ink/25 bg-transparent py-1.5 pr-7 pl-2 text-sm text-muted focus:ring-0"
                        onChange={(e) => {
                          const status = e.currentTarget.value
                          e.currentTarget.value = ''
                          if (status) void add(hit, status as LibraryStatus)
                        }}
                      >
                        <option value="" disabled selected>
                          As…
                        </option>
                        <For
                          each={STATUSES.filter((s) => s.status !== 'dropped')}
                        >
                          {(s) => <option value={s.status}>{s.label}</option>}
                        </For>
                      </select>
                    </div>
                  </Show>
                </Show>
              </li>
            )
          }}
        </For>
      </ul>
    </div>
  )
}
