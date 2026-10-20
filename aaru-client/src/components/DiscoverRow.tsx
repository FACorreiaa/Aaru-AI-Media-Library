import { For, Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import { cardBadge } from '../lib/discover/model'
import type { DiscoverSectionId } from '../lib/discover/model'
import { idKeys, isOnShelf, kindName, kindOf } from '../lib/library/model'
import type {
  CatalogHit,
  LibraryEntry,
  LibraryStatus,
} from '../lib/library/model'
import { addToLibrary } from '../lib/library/server'
import { AddControl } from './AddControl'
import { AddToListDialog } from './AddToListDialog'
import { Row } from './HomeRows'
import { Poster } from './Poster'

/** Text on art: a dark scrim chip, legible on any poster in either theme. */
const chip =
  'rounded-full bg-black/65 px-2 py-0.5 text-[11px] font-semibold text-white'

const keyOf = (hit: CatalogHit) =>
  idKeys(hit.ids).sort()[0] ?? `${hit.title}-${hit.year ?? ''}`

/**
 * One Discover section as a Home-style row: poster cards with the kind and release date on
 * the art, then "On your shelf" or the same Add control Search uses, and "List…".
 */
export function DiscoverRow(props: {
  section: DiscoverSectionId
  title: string
  items: CatalogHit[]
  entries: LibraryEntry[]
  /** The viewer's local "YYYY-MM-DD"; null until the browser knows it (no date badges). */
  today: string | null
  onAdded: (entry: LibraryEntry) => void
  onProblem: (message: string) => void
  action?: JSX.Element
}) {
  // Cards being added right now: a second click waits instead of adding twice.
  const [adding, setAdding] = createSignal<ReadonlySet<string>>(new Set())
  const [listTarget, setListTarget] = createSignal<CatalogHit | null>(null)

  function setBusy(key: string, on: boolean) {
    setAdding((current) => {
      const next = new Set(current)
      if (on) next.add(key)
      else next.delete(key)
      return next
    })
  }

  async function add(hit: CatalogHit, status: LibraryStatus) {
    const key = keyOf(hit)
    if (adding().has(key)) return
    setBusy(key, true)
    try {
      props.onAdded(
        await addToLibrary({
          data: {
            type: hit.type,
            ids: hit.ids,
            title: hit.title,
            year: hit.year,
            status,
          },
        }),
      )
    } catch (error) {
      props.onProblem(
        error instanceof Error
          ? error.message
          : `${hit.title} could not be added.`,
      )
    } finally {
      setBusy(key, false)
    }
  }

  return (
    <>
      <Row title={props.title} action={props.action}>
        <For each={props.items}>
          {(hit) => {
            const kind = kindOf(hit.type, hit.isAnime)
            const badge = () =>
              props.today
                ? cardBadge(props.section, hit.releaseDate, props.today)
                : null
            return (
              <article class="flex w-36 shrink-0 snap-start flex-col md:w-40">
                <div class="relative">
                  <Poster url={hit.posterUrl} kind={kind} />
                  <span class={`absolute top-2 left-2 ${chip}`}>
                    {kindName(kind)}
                  </span>
                  <Show when={badge()}>
                    {(text) => (
                      <span class="absolute right-2 bottom-2 rounded-full bg-accent px-2 py-0.5 text-[11px] font-semibold text-on-accent">
                        {text()}
                      </span>
                    )}
                  </Show>
                </div>
                <p class="mt-2 line-clamp-2 text-sm font-medium">{hit.title}</p>
                <Show when={hit.year}>
                  {(year) => <p class="text-xs text-muted">{year()}</p>}
                </Show>
                <div class="mt-auto flex flex-wrap items-center gap-x-3 gap-y-2 pt-2">
                  <Show
                    when={!isOnShelf(hit, props.entries)}
                    fallback={
                      <span class="text-sm font-medium text-accent">
                        On your shelf
                      </span>
                    }
                  >
                    <AddControl
                      kind={kind}
                      id={`${props.section}-${keyOf(hit)}`}
                      busy={adding().has(keyOf(hit))}
                      onAdd={(status) => void add(hit, status)}
                    />
                  </Show>
                  <button
                    type="button"
                    class="text-sm font-medium text-muted hover:text-ink"
                    aria-label={`Add ${hit.title} to a list`}
                    onClick={() => setListTarget(hit)}
                  >
                    List…
                  </button>
                </div>
              </article>
            )
          }}
        </For>
      </Row>
      <Show when={listTarget()}>
        {(hit) => (
          <AddToListDialog
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
    </>
  )
}
