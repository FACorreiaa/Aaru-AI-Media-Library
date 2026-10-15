import { useRouter } from '@tanstack/solid-router'
import { Wordmark } from './Brand'

/** The branded fallback when a page cannot load: the message, and a way to try again. */
export function RouteError(props: { error: unknown }) {
  const router = useRouter()
  const message = () =>
    props.error instanceof Error && props.error.message
      ? props.error.message
      : 'Something went wrong.'
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col items-center justify-center px-5 text-center">
      <Wordmark class="h-9 w-auto" />
      <h1 class="mt-10 font-display text-3xl font-medium">
        This page did not load
      </h1>
      <p class="mt-3 text-muted">{message()}</p>
      <button
        type="button"
        onClick={() => void router.invalidate()}
        class="mt-8 rounded-full bg-accent px-6 py-3 font-semibold text-on-accent active:scale-[0.98]"
      >
        Try again
      </button>
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
        class="mt-8 rounded-full bg-accent px-6 py-3 font-semibold text-on-accent active:scale-[0.98]"
      >
        Go home
      </a>
    </main>
  )
}
