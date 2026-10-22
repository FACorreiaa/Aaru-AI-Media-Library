import { useRouter } from '@tanstack/solid-router'
import { onMount } from 'solid-js'
import { reportBrowserError } from '../lib/observability/browser'
import { cn } from '../lib/cn'
import { Wordmark } from './Brand'
import { Button, buttonVariants } from './ui/button'

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
  const home = router.state.location.pathname.startsWith('/app') ? '/app' : '/'
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col items-center justify-center px-5 text-center">
      <Wordmark class="h-9 w-auto" to={home} />
      <h1 class="mt-10 font-display text-3xl font-medium">
        This page did not load
      </h1>
      <p class="mt-3 text-muted">{message()}</p>
      <Button
        variant="primary"
        size="lg"
        onClick={() => void router.invalidate()}
        class="mt-8"
      >
        Try again
      </Button>
    </main>
  )
}

/** The branded page for an address that does not exist. */
export function NotFound() {
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col items-center justify-center px-5 text-center">
      <Wordmark class="h-9 w-auto" />
      <h1 class="mt-10 font-display text-3xl font-medium">
        Nothing lives here
      </h1>
      <p class="mt-3 text-muted">This page does not exist, or it moved.</p>
      <a
        href="/"
        class={cn(buttonVariants({ variant: 'primary', size: 'lg' }), 'mt-8')}
      >
        Go home
      </a>
    </main>
  )
}
