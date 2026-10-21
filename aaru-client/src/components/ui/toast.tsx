import { For, createSignal } from 'solid-js'
import { cn } from '../../lib/cn'

// Toasts without Kobalte: a module-level list, shown by a `Toaster` mounted in each route that
// shows toasts (no layout is shared by every /app route). Screen readers hear each message
// from a polite live region that exists before any message is added; the visible stack holds
// the close buttons, so "Close" is not read out with every message. styles.css (`.ui-toast`)
// fades a toast in.

type Toast = { id: number; message: string; tone: 'ink' | 'danger' }

const [toasts, setToasts] = createSignal<Toast[]>([])
let lastId = 0

export type ToastOptions = {
  tone?: 'ink' | 'danger'
  /** Stays until closed or dismissed by code, instead of leaving after 4 s. */
  persistent?: boolean
}

/** Shows `message` as a toast and returns its id for `dismissToast`. */
export function showToast(message: string, options: ToastOptions = {}) {
  const id = ++lastId
  setToasts((list) => [...list, { id, message, tone: options.tone ?? 'ink' }])
  if (!options.persistent) setTimeout(() => dismissToast(id), 4000)
  return id
}

export function dismissToast(id: number) {
  setToasts((list) => list.filter((toast) => toast.id !== id))
}

export function Toaster() {
  return (
    <>
      <div role="status" class="sr-only">
        <For each={toasts()}>{(toast) => <p>{toast.message}</p>}</For>
      </div>
      <div class="pointer-events-none fixed inset-x-4 bottom-4 z-50 mx-auto flex max-w-md flex-col gap-2">
        <For each={toasts()}>
          {(toast) => (
            <div
              class={cn(
                'ui-toast pointer-events-auto flex items-start gap-3 rounded-panel px-4 py-3 text-sm text-paper shadow-lg',
                toast.tone === 'danger' ? 'bg-danger' : 'bg-ink',
              )}
            >
              <p class="flex-1" aria-hidden="true">
                {toast.message}
              </p>
              <button
                type="button"
                aria-label={`Close: ${toast.message}`}
                class="-my-1 -mr-2 grid size-7 shrink-0 place-items-center rounded-full text-base leading-none hover:bg-paper/15"
                onClick={() => dismissToast(toast.id)}
              >
                <span aria-hidden="true">×</span>
              </button>
            </div>
          )}
        </For>
      </div>
    </>
  )
}
