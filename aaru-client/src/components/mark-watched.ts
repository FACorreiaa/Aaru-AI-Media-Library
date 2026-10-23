import { toast } from '~/components/ui'
import { undoAction } from '../lib/history/server'
import type { LibraryEntry } from '../lib/library/model'
import { markedMessage } from '../lib/title/model'
import type { MarkTarget, ShowWatched } from '../lib/title/model'
import { markShowWatched, updateItem } from '../lib/title/server'

// "Mark watched" from a card's menu or the Title room: it applies at once, and the toast offers
// Undo for six seconds instead of a confirm (owner, 2026-10-22).

/** How long an Undo stays on offer. */
const UNDO_MS = 6000

export function toastFailure(err: unknown, fallback: string) {
  toast.error(err instanceof Error ? err.message : fallback)
}

/** A toast for one journaled write, with Undo for six seconds (DESIGN.md §9): a whole-show
 * mark, an approved request, an applied import. `onUndone` runs once the server has taken the
 * action back, so the page can load again. */
export function offerUndo(
  message: string,
  actionId: string,
  onUndone: () => void,
) {
  toast(message, {
    duration: UNDO_MS,
    action: {
      label: 'Undo',
      onClick: () => {
        undoAction({ data: { id: actionId } }).then(onUndone, (err: unknown) =>
          toastFailure(err, 'That could not be undone.'),
        )
      },
    },
  })
}

/** The toast after marking a show watched. Undo only when something changed; `onUndone` runs
 * once the server has put the show back, so the page can ask for it again. */
export function announceShowWatched(
  result: ShowWatched,
  name: string,
  onUndone: () => void,
) {
  const message = markedMessage(result, name)
  const action = result.action
  if (!action) {
    toast(message)
    return
  }
  offerUndo(message, action.id, onUndone)
}

/** Marks the item watched: every aired episode of a show (one action), or a film finished.
 * `onChanged` gets the item as it now stands, or nothing after an undo. */
export async function markItemWatched(
  item: { id: string; name: string; target: MarkTarget },
  onChanged: (entry?: LibraryEntry) => void,
) {
  if (item.target.type === 'show') {
    const result = await markShowWatched({ data: { id: item.id } })
    onChanged(result.entry)
    announceShowWatched(result, item.name, () => onChanged())
    return
  }
  // A film is one status change. Its Undo puts the status back, the same write as a tap.
  const before = item.target.status
  const entry = await updateItem({
    data: { id: item.id, patch: { status: 'finished' } },
  })
  onChanged(entry)
  toast(`Marked ${item.name} watched`, {
    duration: UNDO_MS,
    action: before
      ? {
          label: 'Undo',
          onClick: () => {
            updateItem({
              data: { id: item.id, patch: { status: before } },
            }).then(onChanged, (err: unknown) =>
              toastFailure(err, 'That could not be undone.'),
            )
          },
        }
      : undefined,
  })
}
