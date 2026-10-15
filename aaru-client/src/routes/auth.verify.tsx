import {
  Link,
  createFileRoute,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { z } from 'zod'
import { Wordmark } from '../components/Brand'
import { signInWithEmailLink } from '../lib/session/session'

// The link in the sign-in email (MAGIC_LINK_BASE_URL). The token is spent only when the user
// taps the button, so a mail scanner opening the link does not use it up.
export const Route = createFileRoute('/auth/verify')({
  head: () => ({
    meta: [{ title: 'Sign in · Aaru' }, { name: 'robots', content: 'noindex' }],
  }),
  validateSearch: z.object({ token: z.string().optional() }),
  component: VerifyLink,
})

function VerifyLink() {
  const search = Route.useSearch()
  const router = useRouter()
  const navigate = useNavigate()
  const [working, setWorking] = createSignal(false)
  const [error, setError] = createSignal<string | null>(null)

  async function continueToAaru() {
    const token = search().token
    if (!token || working()) return
    setWorking(true)
    setError(null)
    try {
      await signInWithEmailLink({ data: { token } })
      await router.invalidate()
      await navigate({ to: '/app' })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong.')
    } finally {
      setWorking(false)
    }
  }

  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col justify-center px-5 py-10">
      <Wordmark class="h-9 w-auto" />
      <h1 class="mt-8 font-display text-4xl leading-tight font-medium tracking-tight">
        Sign in to Aaru
      </h1>
      <Show
        when={search().token}
        fallback={
          <p class="mt-4 text-lg leading-relaxed text-muted">
            This link is missing its code. Open the newest email from Aaru, or
            sign in again.
          </p>
        }
      >
        <p class="mt-4 text-lg leading-relaxed text-muted">
          The link works once, for 15 minutes.
        </p>
        <button
          type="button"
          class="mt-10 flex min-h-13 w-full items-center justify-center rounded-full bg-ink px-6 text-base font-semibold text-paper transition-transform active:scale-[0.98] disabled:opacity-50"
          disabled={working()}
          onClick={() => void continueToAaru()}
        >
          {working() ? 'Signing in…' : 'Continue to Aaru'}
        </button>
      </Show>
      <Show when={error()}>
        {(message) => (
          <p role="alert" class="mt-4 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
      <Link
        to="/sign-in"
        class="mt-6 text-sm font-medium text-muted hover:text-ink"
      >
        Sign in another way
      </Link>
    </main>
  )
}
