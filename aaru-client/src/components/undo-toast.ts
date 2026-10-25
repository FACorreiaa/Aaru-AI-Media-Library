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
  offerUndoWith(message, () => undoAction({ data: { id: actionId } }), onUndone)
}

/** The same toast for a write that is not journaled (a Tonight verdict): `undo` takes it back. */
export function offerUndoWith(
  message: string,
  undo: () => Promise<unknown>,
  onUndone: () => void,
) {
  toast(message, {
    duration: UNDO_MS,
    action: {
      label: 'Undo',
      onClick: () => {
        undo().then(onUndone, (err: unknown) =>
          toastFailure(err, 'That could not be undone.'),
        )
      },
    },
  })
}
