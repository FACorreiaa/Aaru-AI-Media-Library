import { toast } from '~/components/ui'
import { undoAction } from '../lib/history/server'

// The Undo toast on its own, so a page that only offers Undo (a plan card, an import) does
// not load the mark-watched writes with it.

/** How long an Undo stays on offer. */
export const UNDO_MS = 6000

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
