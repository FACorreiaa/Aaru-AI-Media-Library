import { For, Show } from 'solid-js'
import { statusOptions } from '../lib/library/model'
import type { LibraryStatus, MediaKind } from '../lib/library/model'

/**
 * Add to the library: the button adds as planned, the menu beside it adds with another
 * status, worded for the title's kind. Shared by Search and Discover. While `busy`, it shows
 * "Adding…" so a second click waits instead of adding twice.
 */
export function AddControl(props: {
  /** The title's kind: decides "Plan to watch" or "Plan to read". */
  kind: MediaKind
  /** Unique per row on the page: names the status menu for its label. */
  id: string
  busy?: boolean
  onAdd: (status: LibraryStatus) => void
}) {
  const selectId = () => `status-${props.id}`
  return (
    <Show
      when={!props.busy}
      fallback={<span class="text-sm text-muted">Adding…</span>}
    >
      <div class="flex items-center overflow-hidden rounded-full border border-ink/25">
        <button
          type="button"
          class="px-4 py-1.5 text-sm font-semibold hover:bg-surface"
          onClick={() => props.onAdd('wishlist')}
        >
          Add
        </button>
        <label class="sr-only" for={selectId()}>
          Add with status
        </label>
        <select
          id={selectId()}
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
            each={statusOptions(props.kind).filter(
              (s) => s.status !== 'dropped',
            )}
          >
            {(s) => <option value={s.status}>{s.label}</option>}
          </For>
        </select>
      </div>
    </Show>
  )
}
