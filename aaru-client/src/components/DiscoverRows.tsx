import { Link } from '@tanstack/solid-router'
import { Index, Show, createSignal } from 'solid-js'
import { markAdded } from '../lib/home/model'
import type { DiscoverRow } from '../lib/home/model'
import { hitKey } from '../lib/library/model'
import type {
  CatalogHit,
  LibraryEntry,
  LibraryStatus,
} from '../lib/library/model'
import { addToLibrary } from '../lib/library/server'
import { AddToListDialog } from './AddToListDialog'
import { DiscoverCard, Row } from './HomeRows'

/**
 * DISC-001: the public rows, as Home shows them under the user's own and as the Discover page
 * shows them alone. The server names and orders the rows; any row id renders. Adding a card
 * flips every card for that title to "In your library" with no refetch.
 */
/**
 * Adding a public card to the library, shared by the Discover rows and the Seasons view: one
 * add per title at a time, the list dialog, and the problem line.
 */
export function createDiscoverAdder(options: {
  onAdded: (key: string, entry: LibraryEntry) => void
  onProblem: (message: string | null) => void
}) {
  // Titles being added right now: a second click waits instead of adding twice.
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
    const key = hitKey(hit)
    if (adding().has(key)) return
    setBusy(key, true)
    options.onProblem(null)
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
      options.onAdded(key, entry)
    } catch (error) {
      options.onProblem(
        error instanceof Error
          ? error.message
          : `${hit.title} could not be added.`,
      )
    } finally {
      setBusy(key, false)
    }
  }

  const ListDialog = () => (
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
  )

  return {
    isAdding: (hit: CatalogHit) => adding().has(hitKey(hit)),
    add,
    openList: (hit: CatalogHit) => setListTarget(hit),
    ListDialog,
  }
}

export function DiscoverRows(props: {
  rows: DiscoverRow[]
  onRowsChange: (rows: DiscoverRow[]) => void
  /** The viewer's local "YYYY-MM-DD"; null until the browser knows it (no date badges). */
  today: string | null
  onAdded?: (entry: LibraryEntry) => void
  onProblem: (message: string | null) => void
}) {
  const adder = createDiscoverAdder({
    onAdded: (key, entry) => {
      props.onRowsChange(markAdded(props.rows, key, entry.id))
      props.onAdded?.(entry)
    },
    onProblem: (message) => props.onProblem(message),
  })

  return (
    <>
      {/* Index, not For: an add replaces the hit objects, and the rows and cards must update
 in place rather than be redrawn, or each row would lose its scroll position. */}
      <Index each={props.rows.filter((row) => row.items.length > 0)}>
        {(row) => (
          <Row
            title={row().title}
            note={row().note}
            action={
              row().id === 'anime_season' ? (
                <Link
                  to="/app/discover"
                  search={{ view: 'seasons', kind: 'anime' }}
                  class="text-sm font-medium text-accent hover:underline"
                >
                  All seasons
                </Link>
              ) : undefined
            }
          >
            <Index each={row().items}>
              {(hit) => (
                <DiscoverCard
                  hit={hit()}
                  rowId={row().id}
                  today={props.today}
                  adding={adder.isAdding(hit())}
                  onAdd={(status) => void adder.add(hit(), status)}
                  onList={() => adder.openList(hit())}
                />
              )}
            </Index>
          </Row>
        )}
      </Index>
      <adder.ListDialog />
    </>
  )
}
