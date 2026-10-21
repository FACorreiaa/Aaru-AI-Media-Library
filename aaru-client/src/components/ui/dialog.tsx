import { onMount, splitProps } from 'solid-js'
import type { JSX } from 'solid-js'
import { cn } from '../../lib/cn'

// A modal on the native <dialog>: the browser gives Esc, focus containment, an inert page and
// focus return for free, so there is no Kobalte here. styles.css adds the enter/exit fade
// (`.ui-dialog`) and locks the page's scroll while one is open, both without JS.

export type DialogProps = Omit<
  JSX.DialogHtmlAttributes<HTMLDialogElement>,
  'ref' | 'onClose'
> & {
  ref?: HTMLDialogElement | ((el: HTMLDialogElement) => void)
  /** Open as soon as it mounts, for dialogs that exist only while shown. */
  openOnMount?: boolean
  /** `sheet` rises from the bottom edge on phones; `center` stays centred; `full` fills the
   *  viewport (it has no backdrop to click). */
  placement?: 'center' | 'sheet' | 'full'
  /** Runs once the dialog has closed, however it closed (Esc, backdrop, a button). */
  onClose?: () => void
}

export function Dialog(props: DialogProps) {
  const [local, rest] = splitProps(props, [
    'ref',
    'openOnMount',
    'placement',
    'onClose',
    'class',
    'children',
  ])
  let dialog: HTMLDialogElement | undefined

  onMount(() => {
    if (local.openOnMount) dialog?.showModal()
  })

  return (
    <dialog
      ref={(el) => {
        dialog = el
        if (typeof local.ref === 'function') local.ref(el)
      }}
      class={cn(
        'ui-dialog bg-paper p-0 text-ink shadow-2xl',
        local.placement === 'sheet'
          ? 'ui-dialog-sheet'
          : local.placement === 'full'
            ? 'ui-dialog-full'
            : 'm-auto rounded-card',
        local.class,
      )}
      onClick={(e) => {
        // A click on the backdrop lands on the <dialog> itself.
        if (e.target === dialog) dialog.close()
      }}
      onClose={() => local.onClose?.()}
      {...rest}
    >
      {local.children}
    </dialog>
  )
}
