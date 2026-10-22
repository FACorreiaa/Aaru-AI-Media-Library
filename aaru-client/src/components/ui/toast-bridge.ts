import { createSignal } from 'solid-js'
import type { toast as somotoToast } from 'somoto'

/**
 * Aaru: the link between the barrel's `toast()` and somoto, which loads on the first toast
 * (sonner.tsx). No somoto code is imported here, only its type.
 */
export type SomotoToast = typeof somotoToast

const [wanted, setWanted] = createSignal(false)

let resolveReady: (toast: SomotoToast) => void = () => {}
const ready = new Promise<SomotoToast>((resolve) => {
  resolveReady = resolve
})

/** True once anything has asked for a toast: the shell then mounts the Toaster. */
export const toasterWanted = wanted

/** Called by the mounted Toaster. somoto only shows toasts published after it subscribes. */
export function toasterReady(toast: SomotoToast) {
  resolveReady(toast)
}

/** Runs `use` with somoto's `toast` once the Toaster is on screen, asking for it if needed. */
export function withToaster(use: (toast: SomotoToast) => void) {
  setWanted(true)
  void ready.then(use)
}

/** Whether a toast has been asked for yet; `dismiss` before that has nothing to dismiss. */
export function toasterRequested() {
  return wanted()
}
