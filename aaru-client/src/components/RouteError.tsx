import { useRouter } from '@tanstack/solid-router'
import { Show, onMount } from 'solid-js'
import { Dynamic } from 'solid-js/web'
import { reportBrowserError } from '../lib/observability/browser'
import { MascotMedallion, Wordmark } from './Brand'

// These two are the router's defaults, so they load with every page. They spell out the
// primary button's look instead of importing Button: that would put Kobalte and tailwind-merge
// (~13 KB gzip) into every page's first load for a page that is almost never seen.
const primary =
  'mt-8 inline-flex items-center justify-center rounded-full bg-primary px-6 py-3 text-base font-semibold text-primary-foreground outline-none transition-[transform,background-color] hover:bg-primary/90 focus-visible:ring-[3px] focus-visible:ring-ring/50 motion-safe:active:scale-[0.98]'

/** The branded fallback when a page cannot load: the message, and a way to try again. */
export function RouteError(props: { error: unknown }) {
  const router = useRouter()
  // The router's boundary catches this before the page's error handler can, so report it here.
  onMount(() => reportBrowserError(props.error))
  const message = () =>
    props.error instanceof Error && props.error.message
      ? props.error.message
      : 'Something went wrong.'
  // A signed-in page that failed keeps its way back into the app, not out to the landing page.
  // Under /app it renders inside the shell's main, beside the sidebar: no second landmark or
  // wordmark there.
  const inApp = router.state.location.pathname.startsWith('/app')
  const home = inApp ? '/app' : '/'
  return (
    <Dynamic
      component={inApp ? 'div' : 'main'}
      class="mx-auto flex max-w-md flex-col items-center justify-center px-5 text-center"
      classList={{ 'min-h-[100dvh]': !inApp, 'min-h-[60dvh]': inApp }}
    >
      <Show when={!inApp}>
        <Wordmark class="mb-10 h-9 w-auto" to={home} />
      </Show>
      <MascotMedallion decorative class="mb-8 w-28" />
      <h1 class="font-display text-3xl font-medium">This page did not load</h1>
      <p class="mt-3 text-muted">{message()}</p>
      {/* eslint-disable-next-line no-restricted-syntax -- see `primary` above */}
      <button
        type="button"
        class={primary}
        onClick={() => void router.invalidate()}
      >
        Try again
      </button>
    </Dynamic>
  )
}

/** The branded page for an address that does not exist. */
export function NotFound() {
  const router = useRouter()
  // UX-010: a missing page under /app leads back into the app, not out to the landing page.
  const home = router.state.location.pathname.startsWith('/app') ? '/app' : '/'
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col items-center justify-center px-5 text-center">
      <Wordmark class="h-9 w-auto" to={home} />
      <MascotMedallion decorative pose="curious" class="mt-10 w-28" />
      <h1 class="mt-8 font-display text-3xl font-medium">Nothing lives here</h1>
      <p class="mt-3 text-muted">This page does not exist, or it moved.</p>
      <a href={home} class={primary}>
        Go home
      </a>
    </main>
  )
}
