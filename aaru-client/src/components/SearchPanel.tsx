import {
  For,
  Show,
  createEffect,
  createSignal,
  onCleanup,
  onMount,
} from 'solid-js'
import { addToLibrary, searchCatalog } from '../lib/library/server'
import { isOnList } from '../lib/lists/model'
import { addToList } from '../lib/lists/server'
import type { ListDetail } from '../lib/lists/server'
import {
  KINDS,
  hitKey,
  isOnShelf,
  kindName,
  kindOf,
} from '../lib/library/model'
import type {
  CatalogHit,
  LibraryEntry,
  LibraryStatus,
  MediaKind,
} from '../lib/library/model'
import { AddControl } from './AddControl'
import { ListAddIcon } from './shell/icons'
import { Poster } from './Poster'
import { AddToListDialog } from './AddToListDialog'
import {
  Button,
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { lastShown } from '../lib/presence'

/** All searches films, shows and anime together; books and albums are never in it, and the last
 * rows of an All search offer them instead. */
export type Scope = MediaKind | 'all'

const SCOPES: Array<{ kind: Scope; label: string }> = [
  { kind: 'all', label: 'All' },
  ...KINDS.map((k) => ({ kind: k.kind, label: k.label })),
]

const PLACEHOLDERS: Partial<Record<Scope, string>> = {
  book: 'Title, author or ISBN',
  album: 'Album or artist',
}

/** APP-004 on the web: scoped search, debounced, with add and an initial status. Given a
 * `list` (LST-003), each hit adds to that list instead of the library. */
export function SearchPanel(props: {
  entries?: LibraryEntry[]
  /** The tab it opens on (UX-087: the empty calendar opens Shows). */
  scope?: Scope
  onAdded?: (entry: LibraryEntry) => void
  onClose: () => void
  list?: ListDetail
  onListChanged?: (detail: ListDetail) => void
}) {
  const [query, setQuery] = createSignal('')
  const [kind, setKind] = createSignal<Scope>(props.scope ?? 'all')
  let input: HTMLInputElement | undefined
  // The routes load this panel lazily, after their dialog has opened: `autofocus` only acts
  // when the dialog opens, so the first mount focuses the field itself.
  onMount(() => input?.focus())
  const [hits, setHits] = createSignal<CatalogHit[]>([])
  const [incomplete, setIncomplete] = createSignal(false)
  const [notice, setNotice] = createSignal<string | undefined>()
  const [searching, setSearching] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  // Hits being added right now: a second click waits instead of adding twice.
  const [adding, setAdding] = createSignal<Set<string>>(new Set())
  const [listTarget, setListTarget] = createSignal<CatalogHit | null>(null)
  const shownListTarget = lastShown(listTarget)
  let latest = 0

  createEffect(() => {
    const text = query().trim()
    const current = kind()
    const scope =
      current === 'all'
        ? 'all'
        : (KINDS.find((k) => k.kind === current)?.search ?? 'movie')
    const ticket = ++latest
    if (text.length < 2) {
      setHits([])
      setIncomplete(false)
      setProblem(null)
      return
    }
    // Debounce: a new keystroke replaces this timer before the request goes out.
    const timer = setTimeout(async () => {
      setSearching(true)
      try {
        const results = await searchCatalog({ data: { q: text, type: scope } })
        if (ticket === latest) {
          setHits(results.items)
          setIncomplete(results.incomplete)
          setNotice(results.notice)
          setProblem(null)
        }
      } catch (error) {
        if (ticket === latest) {
          setHits([])
          setIncomplete(false)
          setProblem(error instanceof Error ? error.message : 'Search failed.')
        }
      } finally {
        if (ticket === latest) setSearching(false)
      }
    }, 300)
    onCleanup(() => clearTimeout(timer))
  })

  const keyOf = hitKey

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
      props.onAdded?.(entry)
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

  async function addToTarget(hit: CatalogHit, list: ListDetail) {
    const key = keyOf(hit)
    if (adding().has(key)) return
    setAdding(new Set([...adding(), key]))
    try {
      const detail = await addToList({
        data: {
          id: list.id,
          mediaRef: {
            type: hit.type,
            ids: hit.ids,
            title: hit.title,
            year: hit.year,
          },
        },
      })
      props.onListChanged?.(detail)
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : `${hit.title} could not be added to ${list.name}.`,
      )
    } finally {
      const next = new Set(adding())
      next.delete(key)
      setAdding(next)
    }
  }

  return (
    <Tabs
      value={kind()}
      onChange={(next) => setKind(next as Scope)}
      class="flex max-h-[85dvh] w-full flex-col gap-0"
    >
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 class="font-display text-2xl font-medium">
          {props.list ? `Add to ${props.list.name}` : 'Search'}
        </h2>
        <Button
          variant="ghost"
          size="bare"
          onClick={() => props.onClose()}
          class="text-sm"
        >
          Done
        </Button>
      </div>
      <div class="flex flex-col gap-3 px-5 pt-4">
        <TextField value={query()} onChange={setQuery}>
          <TextFieldLabel class="sr-only">Search</TextFieldLabel>
          <TextFieldInput
            ref={input}
            type="search"
            autofocus
            autocomplete="off"
            placeholder={PLACEHOLDERS[kind()] ?? 'Title'}
            class="min-h-12 rounded-panel border-transparent bg-surface px-4 text-base placeholder:text-muted/70"
          />
        </TextField>
        <TabsList
          class="-mx-5 flex h-auto w-auto justify-start gap-2 overflow-x-auto rounded-none bg-transparent px-5 ring-0"
          aria-label="Type"
        >
          <For each={SCOPES}>
            {(option) => (
              <TabsTrigger
                value={option.kind}
                class="h-auto flex-none shrink-0 rounded-full border border-line px-4 py-1.5 text-ink transition-colors hover:bg-surface data-[selected]:border-transparent data-[selected]:bg-ink data-[selected]:text-paper"
              >
                {option.label}
              </TabsTrigger>
            )}
          </For>
        </TabsList>
        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>
        <Show when={incomplete() && !searching()}>
          <p class="text-sm text-muted">
            {notice() ?? 'Some results are missing right now.'}
          </p>
        </Show>
      </div>
      {/* One panel for every tab: its value follows the selection, so it stays mounted. */}
      <TabsContent value={kind()} class="mt-3 flex-1 overflow-y-auto px-5 pb-5">
        <ul>
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
                      {(kindOfHit === 'album'
                        ? [hit.byline, hit.year]
                        : [kindName(kindOfHit), hit.year, hit.byline]
                      )
                        .filter(Boolean)
                        .join(' · ')}
                    </p>
                  </div>
                  <Show
                    when={props.list}
                    fallback={
                      // shrink-0: the title wraps, never the actions. Below sm the list button
                      // is its icon, named for screen readers by aria-label.
                      <div class="flex shrink-0 items-center gap-1 sm:gap-2">
                        <Button
                          variant="ghost"
                          size="bare"
                          class="min-h-9 gap-1.5 px-1.5 text-sm"
                          aria-label={`Add ${hit.title} to a list`}
                          title="Add to a list"
                          onClick={() => setListTarget(hit)}
                        >
                          <ListAddIcon class="size-4.5" />
                          <span class="hidden sm:inline">List</span>
                        </Button>
                        <Show
                          when={!isOnShelf(hit, props.entries ?? [])}
                          fallback={
                            <span class="text-sm font-medium text-accent">
                              In your library
                            </span>
                          }
                        >
                          <AddControl
                            hit={hit}
                            adding={adding().has(keyOf(hit))}
                            onAdd={(status) => void add(hit, status)}
                          />
                        </Show>
                      </div>
                    }
                  >
                    {(list) => (
                      <Show
                        when={!isOnList(hit, list().items)}
                        fallback={
                          <span class="text-sm font-medium text-accent">
                            On this list
                          </span>
                        }
                      >
                        <Show
                          when={!adding().has(keyOf(hit))}
                          fallback={
                            <span class="text-sm text-muted">Adding…</span>
                          }
                        >
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => void addToTarget(hit, list())}
                          >
                            Add
                          </Button>
                        </Show>
                      </Show>
                    )}
                  </Show>
                </li>
              )
            }}
          </For>
          <Show
            when={
              kind() === 'all' && !searching() && query().trim().length >= 2
            }
          >
            <li class="py-3">
              <Button
                variant="soft"
                size="bare"
                onClick={() => setKind('book')}
                class="w-full justify-start rounded-panel px-3 py-2 text-left text-sm text-accent"
              >
                Search Books for “{query().trim()}”
              </Button>
              <Button
                variant="soft"
                size="bare"
                onClick={() => setKind('album')}
                class="w-full justify-start rounded-panel px-3 py-2 text-left text-sm text-accent"
              >
                Search Music for “{query().trim()}”
              </Button>
            </li>
          </Show>
        </ul>
      </TabsContent>
      <Show when={shownListTarget()}>
        {(hit) => (
          <AddToListDialog
            open={listTarget() !== null}
            mediaRef={{
              type: hit().type,
              ids: hit().ids,
              title: hit().title,
              year: hit().year,
            }}
            titleName={hit().title}
            onClose={() => setListTarget(null)}
          />
        )}
      </Show>
    </Tabs>
  )
}
