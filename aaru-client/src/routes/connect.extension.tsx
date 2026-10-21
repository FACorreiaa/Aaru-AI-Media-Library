import { createFileRoute, redirect } from '@tanstack/solid-router'
import { Match, Switch, createSignal, onCleanup, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { optionalString } from '../lib/search-params'
import { Wordmark } from '../components/Brand'
import { Button } from '../components/ui/button'
import { connectExtension, revokeConnection } from '../lib/agents/server'
import {
  CONNECTED,
  PING,
  READY,
  READY_TIMEOUT_MS,
  STORE_TIMEOUT_MS,
  TOKEN,
  extensionMessage,
} from '../lib/agents/extension'
import { getSession } from '../lib/session/session'

// SCR-007: the extension opens this page when you press Connect in it. Approving mints a token
// that can only scrobble and hands it to the extension on this page; it is never shown. The
// extension names itself ("Chrome on macOS") in `?name`.
export const Route = createFileRoute('/connect/extension')({
  head: () => ({
    meta: [
      { title: 'Connect the browser extension · Aaru' },
      { name: 'robots', content: 'noindex' },
    ],
  }),
  validateSearch: (search): { name?: string } => {
    const name = optionalString(search.name)?.trim().slice(0, 80)
    return name ? { name } : {}
  },
  beforeLoad: async ({ search }) => {
    const session = await getSession()
    if (!session.signedIn)
      throw redirect({
        to: '/sign-in',
        search: {
          next: `/connect/extension${search.name ? `?name=${encodeURIComponent(search.name)}` : ''}`,
        },
      })
  },
  component: ConnectExtension,
})

function Page(props: { children: JSX.Element }) {
  return (
    <main class="mx-auto flex min-h-[100dvh] max-w-md flex-col justify-center px-4 py-10">
      <Wordmark />
      <div class="mt-8">{props.children}</div>
    </main>
  )
}

/** Waiting for the extension to answer, then the answer, then the result. */
type Stage =
  'looking' | 'missing' | 'ready' | 'connecting' | 'connected' | 'declined'

function ConnectExtension() {
  const search = Route.useSearch()
  const [stage, setStage] = createSignal<Stage>('looking')
  const [problem, setProblem] = createSignal<string | null>(null)
  let stored: (() => void) | undefined

  const self = () => ({ origin: window.location.origin, window })
  function onMessage(event: MessageEvent) {
    const message = extensionMessage(event, self())
    if (message?.type === READY && stage() === 'looking') setStage('ready')
    if (message?.type === CONNECTED) stored?.()
  }

  onMount(() => {
    window.addEventListener('message', onMessage)
    window.postMessage({ type: PING }, window.location.origin)
    const timer = setTimeout(() => {
      if (stage() === 'looking') setStage('missing')
    }, READY_TIMEOUT_MS)
    onCleanup(() => {
      clearTimeout(timer)
      window.removeEventListener('message', onMessage)
    })
  })

  async function approve() {
    setStage('connecting')
    setProblem(null)
    try {
      const token = await connectExtension({ data: { name: search().name } })
      const ok = await new Promise<boolean>((resolve) => {
        const timer = setTimeout(() => resolve(false), STORE_TIMEOUT_MS)
        stored = () => {
          clearTimeout(timer)
          resolve(true)
        }
        window.postMessage(
          { type: TOKEN, secret: token.secret },
          window.location.origin,
        )
      })
      stored = undefined
      if (ok) {
        setStage('connected')
        return
      }
      // The extension never took it: nothing should hold a token nobody uses.
      await revokeConnection({ data: { id: token.id } }).catch(() => {})
      setProblem(
        'The extension did not answer. Open it and press Connect again.',
      )
      setStage('ready')
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'This browser was not connected.',
      )
      setStage('ready')
    }
  }

  return (
    <Page>
      <Switch>
        <Match when={stage() === 'connected'}>
          <h1 class="font-display text-3xl font-medium">Connected</h1>
          <p class="mt-3 text-muted">
            What you finish on Netflix, Disney+ and Prime Video in this browser
            is now marked watched in Aaru. You can close this tab.
          </p>
        </Match>
        <Match when={stage() === 'declined'}>
          <h1 class="font-display text-3xl font-medium">Not connected</h1>
          <p class="mt-3 text-muted">
            Nothing was shared. Press Connect in the extension when you change
            your mind.
          </p>
        </Match>
        <Match when={stage() === 'missing'}>
          <h1 class="font-display text-3xl font-medium">
            The extension isn’t here
          </h1>
          <p class="mt-3 text-muted">
            Install Aaru for Chrome or Firefox, then click it in the toolbar and
            press Connect. It opens this page again.
          </p>
        </Match>
        <Match when={true}>
          <h1 class="font-display text-3xl font-medium">
            Connect {search().name ?? 'this browser'} to Aaru?
          </h1>
          <p class="mt-3 text-muted">
            It will mark episodes and films you finish on Netflix, Disney+ and
            Prime Video. It can’t read your library. Revoke it any time in
            Settings → Connections.
          </p>
          <div class="mt-6 flex flex-wrap gap-2">
            <Button
              variant="primary"
              disabled={stage() !== 'ready'}
              onClick={() => void approve()}
            >
              {stage() === 'connecting' ? 'Connecting…' : 'Approve'}
            </Button>
            <Button
              disabled={stage() === 'connecting'}
              onClick={() => setStage('declined')}
            >
              Not now
            </Button>
          </div>
          <p
            role="alert"
            class="mt-4 min-h-5 text-sm text-danger"
            classList={{ invisible: !problem() }}
          >
            {problem()}
          </p>
        </Match>
      </Switch>
    </Page>
  )
}
