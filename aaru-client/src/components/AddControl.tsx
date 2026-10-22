import { For, Show } from 'solid-js'
import { kindOf, statusLabel, statusOptions } from '../lib/library/model'
import type { CatalogHit, LibraryStatus } from '../lib/library/model'
import {
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuTrigger,
} from '~/components/ui'

/**
 * Add to the library: the button adds as planned, the "As…" menu beside it adds with another
 * status, worded for the title's kind ("Plan to watch", "Plan to read"). Shared by Search,
 * Discover, Home's Discover rows and a list's members (UX-072). While `adding`, it shows
 * "Adding…" so a second click waits instead of adding twice.
 */
export function AddControl(props: {
  hit: CatalogHit
  adding: boolean
  onAdd: (status: LibraryStatus) => void
  /** Kept for callers that render one title twice; the menu needs no ids of its own. */
  idPrefix?: string
}) {
  const kind = () => kindOf(props.hit.type, props.hit.isAnime)
  return (
    <Show
      when={!props.adding}
      fallback={<span class="text-sm text-muted">Adding…</span>}
    >
      <div class="flex items-center overflow-hidden rounded-full border border-ink/25">
        <Button
          variant="soft"
          size="bare"
          class="rounded-none px-4 py-1.5 text-sm font-semibold"
          aria-label={`Add ${props.hit.title}: ${statusLabel('wishlist', kind())}`}
          onClick={() => props.onAdd('wishlist')}
        >
          Add
        </Button>
        <DropdownMenu placement="bottom-end">
          <DropdownMenuTrigger
            as={Button}
            variant="soft"
            size="bare"
            class="rounded-none border-l border-ink/25 py-1.5 pr-3 pl-2.5 text-sm text-muted"
            aria-label={`Add ${props.hit.title} with status`}
          >
            As…
          </DropdownMenuTrigger>
          <DropdownMenuPortal>
            <DropdownMenuContent class="min-w-44 rounded-panel border-line bg-paper p-1">
              <For
                each={statusOptions(kind()).filter(
                  (s) => s.status !== 'dropped',
                )}
              >
                {(s) => (
                  <DropdownMenuItem
                    class="min-h-10 rounded-[10px] px-3"
                    onSelect={() => props.onAdd(s.status)}
                  >
                    {s.label}
                  </DropdownMenuItem>
                )}
              </For>
            </DropdownMenuContent>
          </DropdownMenuPortal>
        </DropdownMenu>
      </div>
    </Show>
  )
}
