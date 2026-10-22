/**
 * Focus for a dialog that opens without a Kobalte trigger and renders its body late (Search: a
 * lazy panel, remounted on each open).
 *
 * Opening: Kobalte looks for something to focus as the dialog mounts, before the panel is in
 * it, and a task later focuses the first button it finds ("Done"), after the panel had already
 * focused its own field. `focusFieldOnOpen` takes that over: one task later it leaves focus where
 * the panel put it, or moves it to the `autofocus` field, or to the dialog while the panel loads.
 *
 * Closing: with no trigger, Kobalte sends focus back to whatever held it at mount, often the
 * page body. `createFocusReturn` remembers the control that opened the dialog and returns there.
 */
export function focusFieldOnOpen(event: Event) {
  event.preventDefault()
  const dialog = event.currentTarget as HTMLElement | null
  if (!dialog) return
  setTimeout(() => {
    if (dialog.contains(document.activeElement)) return
    const field = dialog.querySelector<HTMLElement>('[autofocus]')
    ;(field ?? dialog).focus({ preventScroll: true })
  }, 0)
}

export function createFocusReturn() {
  let opener: HTMLElement | null = null
  return {
    /** Call as the dialog opens. `from` is the clicked control: Safari does not focus a button
     * on click, so `document.activeElement` alone would be the body. */
    remember(from?: Element | null) {
      const active = document.activeElement
      const candidate =
        from ?? (active && active !== document.body ? active : null)
      opener = candidate instanceof HTMLElement ? candidate : null
    },
    /** The dialog's `onCloseAutoFocus`. */
    restore(event: Event) {
      const target = opener
      opener = null
      if (!target?.isConnected) return
      event.preventDefault()
      target.focus({ preventScroll: true })
    },
  }
}
