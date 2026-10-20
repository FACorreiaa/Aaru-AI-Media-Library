import { For, Show } from 'solid-js'
import {
  hitKey,
  kindOf,
  statusLabel,
  statusOptions,
} from '../lib/library/model'
import type { CatalogHit, LibraryStatus } from '../lib/library/model'

/**
 * Add to the library: the button adds as planned, the "As…" menu beside it adds with another
 * status, worded for the title's kind ("Plan to watch", "Plan to read"). Shared by Search,
 * Discover and Home's Discover rows. While `adding`, it shows "Adding…" so a second click
 * waits instead of adding twice.
 */
export function AddControl(props: {
  hit: CatalogHit
  adding: boolean
  onAdd: (status: LibraryStatus) => void
  /** Id prefix, so one title shown twice on a page keeps unique ids. */
  idPrefix?: string
}) {
  const id = () => `${props.idPrefix ?? 'status'}-${hitKey(props.hit)}`
  const kind = () => kindOf(props.hit.type, props.hit.isAnime)
  return (
    <Show
      when={!props.adding}
      fallback={<span class="text-sm text-muted">Adding…</span>}
    >
      <div class="flex items-center overflow-hidden rounded-full border border-ink/25">
        <button
          type="button"
          class="px-4 py-1.5 text-sm font-semibold hover:bg-surface"
          aria-label={`Add ${props.hit.title}: ${statusLabel('wishlist', kind())}`}
          onClick={() => props.onAdd('wishlist')}
        >
          Add
        </button>
        <label class="sr-only" for={id()}>
          Add {props.hit.title} with status
        </label>
        <select
          id={id()}
          class="border-0 border-l border-ink/25 bg-transparent py-1.5 pr-7 pl-2 text-sm text-muted focus:ring-0"
          onChange={(e) => {
            const status = e.currentTarget.value
            e.currentTarget.value = ''
            if (status) props.onAdd(status as LibraryStatus)
          }}
        >
          <option value="" disabled selected>
            As…
          </option>
          <For
            each={statusOptions(kind()).filter((s) => s.status !== 'dropped')}
          >
            {(s) => <option value={s.status}>{s.label}</option>}
          </For>
        </select>
      </div>
    </Show>
  )
}
