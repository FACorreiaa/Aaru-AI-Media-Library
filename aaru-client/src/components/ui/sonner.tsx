import type { ExternalToast } from 'somoto'
import type { ComponentProps, JSX } from 'solid-js'
import { Show, Suspense, lazy } from 'solid-js'
import type { SomotoToast } from './toast-bridge'
import { toasterRequested, toasterWanted, withToaster } from './toast-bridge'

// Aaru: somoto (~8.5 KB gz) loads on the first toast, not with every signed-in page. `toast()`
// keeps somoto's shape and answers its id at once, so `toast.dismiss(id)` works as before; the
// toast itself shows once the Toaster has mounted.

const ToasterView = lazy(() => import('./toaster-view'))

type Kind = 'success' | 'info' | 'warning' | 'error' | 'message' | 'loading'

let sequence = 0

function show(kind?: Kind) {
  return (message: JSX.Element, data?: ExternalToast): string | number => {
    const id = data?.id ?? `aaru-toast-${String(++sequence)}`
    withToaster((somoto: SomotoToast) => {
      const send = kind ? somoto[kind] : somoto
      send(message, { ...data, id })
    })
    return id
  }
}

/** The one way to show a toast. Callers import it from the barrel, never from somoto. */
export const toast = Object.assign(show(), {
  success: show('success'),
  info: show('info'),
  warning: show('warning'),
  error: show('error'),
  message: show('message'),
  loading: show('loading'),
  dismiss: (id?: string | number) => {
    if (toasterRequested()) withToaster((somoto) => void somoto.dismiss(id))
    return id
  },
})

/** Mounted once by the shell; renders nothing until the first `toast()`. */
export const Toaster = (props: ComponentProps<typeof ToasterView>) => (
  <Show when={toasterWanted()}>
    {/* Its own boundary, so loading somoto never suspends the page around it. */}
    <Suspense>
      <ToasterView {...props} />
    </Suspense>
  </Show>
)
