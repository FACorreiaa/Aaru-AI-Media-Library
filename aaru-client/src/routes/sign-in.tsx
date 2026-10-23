import {
  createFileRoute,
  redirect,
  useNavigate,
  useRouter,
} from '@tanstack/solid-router'
import { Show, createSignal, onMount } from 'solid-js'
import { optionalString } from '../lib/search-params'
import { safeNext } from '../lib/oauth/model'
import { rememberNext } from '../lib/session/pending-next'
import { AppleSignInButton } from '../components/AppleSignInButton'
import type { AppleCredential } from '../components/AppleSignInButton'
import { GoogleSignInButton } from '../components/GoogleSignInButton'
import type { GoogleCredential } from '../components/GoogleSignInButton'
import { MascotMedallion, Wordmark } from '../components/Brand'
import { LegalLinks } from '../components/LegalPage'
import {
  Button,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import {
  getSession,
  getSignInConfig,
  sendCode,
  signInWithApple,
  signInWithCode,
  signInWithGoogle,
} from '../lib/session/session'
import { forgetAccount } from '../lib/session/query'
import { forgetTonight } from '../lib/home/tonight-cache'

// The web twin of the Apple apps' welcome screen and email sheet (DESIGN.md §0).
export const Route = createFileRoute('/sign-in')({
  head: () => ({ meta: [{ title: 'Sign in · Aaru' }] }),
  // `next`: where to return after signing in, e.g. an OAuth consent page (OUT-004).
  validateSearch: (search): { next?: string } => ({
    next: optionalString(search.next),
  }),
  beforeLoad: async ({ search, context }) => {
    const session = await getSession()
    if (session.signedIn) throw redirect({ href: safeNext(search.next) })
    // Signed out (or the session just ended): the last account's pages leave this tab.
    forgetAccount(context.queryClient)
  },
  loader: () => getSignInConfig(),
  component: SignIn,
})

type Step = 'choose' | 'email' | 'code'

function SignIn() {
  const config = Route.useLoaderData()
  const router = useRouter()
  const navigate = useNavigate()
  const search = Route.useSearch()
  const [step, setStep] = createSignal<Step>('choose')
  const [email, setEmail] = createSignal('')
  const [code, setCode] = createSignal('')
  const [working, setWorking] = createSignal(false)
  // Signed out: the last account's Tonight leaves this browser too.
  onMount(forgetTonight)
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
    await navigate({ href: safeNext(search().next) })
  }

  const submitEmail = (event: SubmitEvent) => {
    event.preventDefault()
    void run(async () => {
      await sendCode({ data: { email: email() } })
      // The email also carries a link; it opens in a new tab without this page's `next`.
      rememberNext(search().next)
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
    'min-h-12 rounded-panel border-transparent bg-surface px-4 text-base placeholder:text-muted/70'
  // As tall as the Apple button above it.
  const tall = 'min-h-13 w-full text-base'

  return (
    <main class="mx-auto grid min-h-[100dvh] max-w-5xl items-center gap-12 px-5 py-10 md:grid-cols-2 md:px-8">
      <MascotMedallion class="mx-auto hidden w-full max-w-sm md:block" />
      <div class="w-full max-w-md">
        <Wordmark class="h-9 w-auto" />
        <h1 class="mt-8 font-display text-4xl leading-tight font-medium tracking-tight text-balance">
          <Show
            when={step() === 'code'}
            fallback="Everything you watch, read and listen to, in one library."
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
            <Button
              variant="outline"
              size="lg"
              class={tall}
              onClick={() => go('email')}
            >
              Continue with email
            </Button>
          </Show>

          <Show when={step() === 'email'}>
            <form class="flex flex-col gap-3" onSubmit={submitEmail}>
              <TextField value={email()} onChange={setEmail} required>
                <TextFieldLabel>Email</TextFieldLabel>
                <TextFieldInput
                  id="email"
                  type="email"
                  autocomplete="email"
                  autofocus
                  placeholder="you@example.com"
                  class={field}
                />
              </TextField>
              <Show when={error()}>
                {(message) => (
                  <p role="alert" class="text-sm text-danger">
                    {message()}
                  </p>
                )}
              </Show>
              <Button
                variant="outline"
                type="submit"
                size="lg"
                class={tall}
                disabled={working() || !email().includes('@')}
              >
                {working() ? 'Sending…' : 'Send code'}
              </Button>
              <Button
                variant="ghost"
                size="bare"
                class="text-sm"
                onClick={() => go('choose')}
              >
                Back
              </Button>
            </form>
          </Show>

          <Show when={step() === 'code'}>
            <form class="flex flex-col gap-3" onSubmit={submitCode}>
              <TextField value={code()} onChange={setCode} required>
                <TextFieldLabel>Code</TextFieldLabel>
                <TextFieldInput
                  id="code"
                  inputmode="numeric"
                  autocomplete="one-time-code"
                  autofocus
                  placeholder="123 456"
                  class={`${field} tracking-[0.2em]`}
                />
              </TextField>
              <Show when={error()}>
                {(message) => (
                  <p role="alert" class="text-sm text-danger">
                    {message()}
                  </p>
                )}
              </Show>
              <Button
                variant="outline"
                type="submit"
                size="lg"
                class={tall}
                disabled={working() || code().replace(/\D/g, '').length !== 6}
              >
                {working() ? 'Signing in…' : 'Sign in'}
              </Button>
              <Button
                variant="ghost"
                size="bare"
                class="text-sm"
                onClick={() => {
                  setCode('')
                  go('email')
                }}
              >
                Use a different email or send a new code
              </Button>
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
