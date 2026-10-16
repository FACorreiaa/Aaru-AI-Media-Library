import {
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { AppleSignInButton } from '../components/AppleSignInButton'
import type { AppleCredential } from '../components/AppleSignInButton'
import { GoogleSignInButton } from '../components/GoogleSignInButton'
import type { GoogleCredential } from '../components/GoogleSignInButton'
import { MascotMedallion, Wordmark } from '../components/Brand'
import { LegalLinks } from '../components/LegalPage'
import {
  getSession,
  getSignInConfig,
  sendCode,
  signInWithApple,
  signInWithCode,
  signInWithGoogle,
} from '../lib/session/session'

// The web twin of the Apple apps' welcome screen and email sheet (DESIGN.md §0).
export const Route = createFileRoute('/sign-in')({
  head: () => ({ meta: [{ title: 'Sign in · Aaru' }] }),
  beforeLoad: async () => {
    const session = await getSession()
    if (session.signedIn) throw redirect({ to: '/app' })
  },
  loader: () => getSignInConfig(),
  component: SignIn,
})

type Step = 'choose' | 'email' | 'code'

function SignIn() {
  const config = Route.useLoaderData()
  const router = useRouter()
  const navigate = useNavigate()
  const [step, setStep] = createSignal<Step>('choose')
  const [email, setEmail] = createSignal('')
  const [code, setCode] = createSignal('')
  const [working, setWorking] = createSignal(false)
  const [error, setError] = createSignal<string | null>(null)

  async function run(action: () => Promise<void>) {
    if (working()) return
    setWorking(true)
    setError(null)
    try {
      await action()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong.')
    } finally {
      setWorking(false)
    }
  }

  /** Moves to a step and focuses its field once it renders. */
  function go(next: Step) {
    setStep(next)
    setError(null)
    queueMicrotask(() => document.getElementById(next)?.focus())
  }

  async function signedIn() {
    await router.invalidate()
    await navigate({ to: '/app' })
  }

  const submitEmail = (event: SubmitEvent) => {
    event.preventDefault()
    void run(async () => {
      await sendCode({ data: { email: email() } })
      go('code')
    })
  }

  const submitCode = (event: SubmitEvent) => {
    event.preventDefault()
    void run(async () => {
      await signInWithCode({ data: { email: email(), code: code() } })
      await signedIn()
    })
  }

  const apple = (credential: AppleCredential) =>
    void run(async () => {
      await signInWithApple({ data: credential })
      await signedIn()
    })

  const google = (credential: GoogleCredential) =>
    void run(async () => {
      await signInWithGoogle({ data: credential })
      await signedIn()
    })

  const field =
    'min-h-12 w-full rounded-[14px] border-0 bg-surface px-4 text-base text-ink placeholder:text-muted/70 focus:ring-2 focus:ring-accent focus:outline-none'
  const outline =
    'flex min-h-13 w-full items-center justify-center rounded-full border border-ink/25 px-6 text-base font-semibold text-ink transition-transform active:scale-[0.98] disabled:opacity-50'

  return (
    <main class="mx-auto grid min-h-[100dvh] max-w-5xl items-center gap-12 px-5 py-10 md:grid-cols-2 md:px-8">
      <MascotMedallion class="mx-auto hidden w-full max-w-sm md:block" />
      <div class="w-full max-w-md">
        <Wordmark class="h-9 w-auto" />
        <h1 class="mt-8 font-display text-4xl leading-tight font-medium tracking-tight text-balance">
          <Show
            when={step() === 'code'}
            fallback="Everything you watch and read, on one shelf."
          >
            Check your email
          </Show>
        </h1>
        <p class="mt-4 text-lg leading-relaxed text-muted">
          <Show
            when={step() === 'code'}
            fallback="Films, shows, anime and books in one calm library."
          >
            We sent a six-digit code to {email()}. It works once, for 15
            minutes.
          </Show>
        </p>

        <div class="mt-10 flex flex-col gap-3">
          <Show when={step() === 'choose'}>
            <Show when={config().appleServicesId}>
              {(servicesId) => (
                <AppleSignInButton
                  servicesId={servicesId()}
                  onCredential={apple}
                  onError={setError}
                />
              )}
            </Show>
            <Show when={config().googleClientId}>
              {(clientId) => (
                <GoogleSignInButton
                  clientId={clientId()}
                  onCredential={google}
                  onError={setError}
                />
              )}
            </Show>
            <button type="button" class={outline} onClick={() => go('email')}>
              Continue with email
            </button>
          </Show>

          <Show when={step() === 'email'}>
            <form class="flex flex-col gap-3" onSubmit={submitEmail}>
              <label for="email" class="text-sm font-medium">
                Email
              </label>
              <input
                id="email"
                type="email"
                autocomplete="email"
                required
                autofocus
                placeholder="you@example.com"
                class={field}
                value={email()}
                onInput={(e) => setEmail(e.currentTarget.value)}
              />
              <Show when={error()}>
                {(message) => (
                  <p role="alert" class="text-sm text-danger">
                    {message()}
                  </p>
                )}
              </Show>
              <button
                type="submit"
                class={outline}
                disabled={working() || !email().includes('@')}
              >
                {working() ? 'Sending…' : 'Send code'}
              </button>
              <button
                type="button"
                class="text-sm font-medium text-muted hover:text-ink"
                onClick={() => go('choose')}
              >
                Back
              </button>
            </form>
          </Show>

          <Show when={step() === 'code'}>
            <form class="flex flex-col gap-3" onSubmit={submitCode}>
              <label for="code" class="text-sm font-medium">
                Code
              </label>
              <input
                id="code"
                inputmode="numeric"
                autocomplete="one-time-code"
                required
                autofocus
                placeholder="123 456"
                class={`${field} tracking-[0.2em]`}
                value={code()}
                onInput={(e) => setCode(e.currentTarget.value)}
              />
              <Show when={error()}>
                {(message) => (
                  <p role="alert" class="text-sm text-danger">
                    {message()}
                  </p>
                )}
              </Show>
              <button
                type="submit"
                class={outline}
                disabled={working() || code().replace(/\D/g, '').length !== 6}
              >
                {working() ? 'Signing in…' : 'Sign in'}
              </button>
              <button
                type="button"
                class="text-sm font-medium text-muted hover:text-ink"
                onClick={() => {
                  setCode('')
                  go('email')
                }}
              >
                Use a different email or send a new code
              </button>
            </form>
          </Show>

          <Show when={step() === 'choose' && error()}>
            {(message) => (
              <p role="alert" class="text-sm text-danger">
                {message()}
              </p>
            )}
          </Show>
        </div>
        <LegalLinks class="mt-12 flex gap-4 text-sm text-muted" />
      </div>
    </main>
  )
}
