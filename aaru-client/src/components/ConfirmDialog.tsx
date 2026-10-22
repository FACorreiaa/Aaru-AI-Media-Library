import { Show } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogPortal,
  AlertDialogTitle,
  Button,
} from '~/components/ui'

/**
 * Asks before something that cannot be taken back, on shadcn-solid's AlertDialog. Opens while
 * `open` is true; focus starts on Cancel, so Enter never confirms by accident. Esc and the
 * overlay cancel. Confirm is a plain button, not a close button: the owner closes the dialog
 * when the work is done, and `busy` keeps it open and disabled meanwhile.
 */
export function ConfirmDialog(props: {
  open: boolean
  title: string
  description?: JSX.Element
  confirmLabel: string
  cancelLabel?: string
  busy?: boolean
  onConfirm: () => void
  onCancel: () => void
}) {
  let cancel: HTMLButtonElement | undefined
  return (
    <AlertDialog
      open={props.open}
      onOpenChange={(open) => {
        if (!open) props.onCancel()
      }}
    >
      <AlertDialogPortal>
        <AlertDialogContent
          class="w-[min(26rem,calc(100vw-2rem))]"
          onOpenAutoFocus={(event) => {
            event.preventDefault()
            cancel?.focus()
          }}
        >
          <AlertDialogHeader>
            <AlertDialogTitle>{props.title}</AlertDialogTitle>
            <Show when={props.description}>
              <AlertDialogDescription>
                {props.description}
              </AlertDialogDescription>
            </Show>
          </AlertDialogHeader>
          <AlertDialogFooter class="mt-2 flex-row flex-wrap justify-end">
            <AlertDialogCancel ref={cancel} class="min-h-0 px-4 py-1.5 text-sm">
              {props.cancelLabel ?? 'Cancel'}
            </AlertDialogCancel>
            <Button
              variant="destructive"
              size="sm"
              disabled={props.busy}
              onClick={() => props.onConfirm()}
            >
              {props.confirmLabel}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialogPortal>
    </AlertDialog>
  )
}
