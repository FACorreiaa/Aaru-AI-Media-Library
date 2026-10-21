import { Show, createEffect, createUniqueId } from 'solid-js'
import type { JSX } from 'solid-js'
import { Button } from './button'
import { Dialog } from './dialog'

/**
 * Asks before something that cannot be taken back. Opens while `open` is true; focus starts on
 * Cancel, so Enter never confirms by accident. Esc and the backdrop cancel.
 */
export function AlertDialog(props: {
  open: boolean
  title: string
  description?: JSX.Element
  confirmLabel: string
  cancelLabel?: string
  busy?: boolean
  onConfirm: () => void
  onCancel: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const titleId = createUniqueId()

  createEffect(() => {
    if (!dialog) return
    if (props.open && !dialog.open) dialog.showModal()
    if (!props.open && dialog.open) dialog.close()
  })

  return (
    <Dialog
      ref={dialog}
      role="alertdialog"
      aria-labelledby={titleId}
      class="w-[min(26rem,calc(100vw-2rem))] p-6"
      onClose={() => {
        if (props.open) props.onCancel()
      }}
    >
      <h2 id={titleId} class="font-display text-xl font-medium">
        {props.title}
      </h2>
      <Show when={props.description}>
        <div class="mt-2 text-sm text-muted">{props.description}</div>
      </Show>
      <div class="mt-6 flex flex-wrap justify-end gap-2">
        <Button size="sm" autofocus onClick={() => props.onCancel()}>
          {props.cancelLabel ?? 'Cancel'}
        </Button>
        <Button
          variant="danger"
          size="sm"
          disabled={props.busy}
          onClick={() => props.onConfirm()}
        >
          {props.confirmLabel}
        </Button>
      </div>
    </Dialog>
  )
}
