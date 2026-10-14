import {
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { createSignal } from 'solid-js'
import { Wordmark } from '../components/Brand'
import { getSession, signOut } from '../lib/session/session'

// The signed-in shell. WEB-001 grows it into home rows, the week grid and the library.
export const Route = createFileRoute('/app')({
  head: () => ({ meta: [{ title: 'Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (!session.signedIn) throw redirect({ to: '/sign-in' })
    return { session }
  },
  component: Signedin,
})

function Signedin() {
  const context = Route.useRouteContext()
  const router = useRouter()
  const navigate = useNavigate()
  const [leaving, setLeaving] = createSignal(false)

  async function leave() {
    setLeaving(true)
    await signOut()
    await router.invalidate()
    await navigate({ to: '/' })
  }

  return (
    <div class="min-h-[100dvh]">
      <header class="mx-auto flex h-18 max-w-6xl items-center justify-between px-5 md:px-8">
        <Wordmark />
        <button
          type="button"
          onClick={leave}
          disabled={leaving()}
          class="text-sm font-medium text-muted transition-colors hover:text-ink disabled:opacity-50"
        >
          Sign out
        </button>
      </header>
      <main class="mx-auto flex max-w-xl flex-col items-center px-5 pt-24 text-center">
        <h1 class="font-display text-4xl font-medium tracking-tight">
          {context().session.displayName
            ? `Welcome, ${context().session.displayName}`
            : 'Signed in'}
        </h1>
        <p class="mt-4 text-lg text-muted">Your library is next.</p>
      </main>
    </div>
  )
}
