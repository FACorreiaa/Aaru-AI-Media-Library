import { For, Show, createEffect, createSignal, onCleanup } from 'solid-js'
import {
  Button,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { KINDS, kindOf } from '../../lib/library/model'
import type { CatalogHit, MediaKind } from '../../lib/library/model'
import { searchCatalog } from '../../lib/library/server'
import { Poster } from '../Poster'
import { Segmented } from '../Segmented'

/**
 * Search the catalog and pick one title: the same search as Add, scoped by kind. Used to make a
 * title channel, add to a List channel, start a watch party, and match an import row by hand.
 */
export function TitlePicker(props: {
  onPick: (hit: CatalogHit) => void
  /** Kinds to offer; a watch party has no books. */
  kinds?: MediaKind[]
  busy?: boolean
  /** Where the search starts: an import row's own title and kind. */
  initialQuery?: string
  initialKind?: MediaKind
}) {
  const kinds = () =>
    KINDS.filter((k) => !props.kinds || props.kinds.includes(k.kind))
  const offered = kinds().some((k) => k.kind === props.initialKind)
  const [kind, setKind] = createSignal<MediaKind>(
    props.initialKind && offered
      ? props.initialKind
      : (kinds()[0]?.kind ?? 'film'),
  )
  const [query, setQuery] = createSignal(props.initialQuery ?? '')
  const [hits, setHits] = createSignal<CatalogHit[]>([])
  const [searching, setSearching] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
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
    const timer = setTimeout(async () => {
      setSearching(true)
      try {
        const results = await searchCatalog({ data: { q: text, type: scope } })
        if (ticket === latest) {
          setHits(results.items.slice(0, 8))
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

  return (
    <div>
      <Segmented
        label="Kind"
        variant="chip"
        options={kinds().map((k) => ({ value: k.kind, label: k.label }))}
        value={kind()}
        onChange={setKind}
        itemClass="min-h-8 px-3 text-sm"
      />
      <TextField value={query()} onChange={setQuery} class="mt-3">
        <TextFieldLabel class="sr-only">Search titles</TextFieldLabel>
        <TextFieldInput
          type="search"
          autofocus
          placeholder="Search by title"
          class="w-full rounded-xl border-0 bg-surface px-4 text-base md:text-base"
        />
      </TextField>
      <Show when={problem()}>
        {(text) => (
          <p role="alert" class="mt-2 text-sm text-danger">
            {text()}
          </p>
        )}
      </Show>
      <ul class="mt-2 max-h-72 overflow-y-auto" aria-busy={searching()}>
        <For each={hits()}>
          {(hit) => (
            <li>
              <Button
                variant="soft"
                size="bare"
                disabled={props.busy}
                onClick={() => props.onPick(hit)}
                class="flex w-full justify-start gap-3 rounded-xl px-2 py-1.5 text-left font-normal"
              >
                <Poster
                  url={hit.posterUrl}
                  kind={kindOf(hit.type, hit.isAnime)}
                  class="w-9 shrink-0"
                />
                <span class="min-w-0 flex-1">
                  <span class="block truncate font-medium">{hit.title}</span>
                  <span class="block truncate text-xs text-muted">
                    {(hit.type === 'album'
                      ? [hit.byline, hit.year]
                      : [hit.year, hit.byline]
                    )
                      .filter(Boolean)
                      .join(' · ')}
                  </span>
                </span>
              </Button>
            </li>
          )}
        </For>
      </ul>
      <Show
        when={query().trim().length >= 2 && !searching() && hits().length === 0}
      >
        <p class="mt-2 text-sm text-muted">Nothing found.</p>
      </Show>
    </div>
  )
}
