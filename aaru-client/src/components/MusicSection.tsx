import { Link } from '@tanstack/solid-router'
import { For, Show, createMemo, createSignal, onCleanup } from 'solid-js'
import {
  FIRST_LISTEN_POLL_MS,
  FIRST_LISTEN_WAIT_MS,
  SCROBBLERS,
  isNewListen,
  listenDetail,
  listenTitle,
  scrobblerLabel,
  scrobblerSummary,
} from '../lib/music/model'
import type { Scrobbler } from '../lib/music/model'
import { lastUsedLabel } from '../lib/stremio/model'
import { cn } from '../lib/cn'
import { AlertDialog } from './ui/alert-dialog'
import { Button, buttonVariants } from './ui/button'
import { RadioGroup, RadioGroupItem } from './ui/radio-group'
import { showToast } from './ui/toast'
import { cardClass } from './ui/card'
import {
  connectScrobbler,
  latestListen,
  listScrobblers,
  revokeScrobbler,
} from '../lib/music/server'
import type {
  AgentToken,
  Listen,
  MusicConnection,
  MusicSetup,
} from '../lib/music/server'

// MUS-007: point a music scrobbler at Aaru. Pick the scrobbler, connect, and its steps come
// back with the token filled in, shown once. Then Settings waits for the first listen so the
// user knows the setup worked.
export function MusicSection(props: {
  scrobblers: AgentToken[]
  latest: Listen | null
}) {
  const [scrobblers, setScrobblers] = createSignal(props.scrobblers)
  const [latest, setLatest] = createSignal(props.latest)
  const [choice, setChoice] = createSignal<Scrobbler>('web_scrobbler')
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [fresh, setFresh] = createSignal<MusicConnection | null>(null)
  // Waiting for the first listen after connecting; `heard` is the one that arrived.
  const [waiting, setWaiting] = createSignal(false)
  const [heard, setHeard] = createSignal<Listen | null>(null)
  const [pending, setPending] = createSignal<AgentToken | null>(null)
  const [revoking, setRevoking] = createSignal(false)
  const asked = createMemo<AgentToken | null>((last) => pending() ?? last, null)

  let poll: ReturnType<typeof setInterval> | undefined
  const stopWaiting = () => {
    clearInterval(poll)
    poll = undefined
    setWaiting(false)
  }
  onCleanup(stopWaiting)

  const fail = (error: unknown, fallback: string) =>
    setProblem(error instanceof Error ? error.message : fallback)

  function waitForFirstListen(seen: Listen | null) {
    stopWaiting()
    setHeard(null)
    setWaiting(true)
    const until = Date.now() + FIRST_LISTEN_WAIT_MS
    poll = setInterval(() => {
      if (Date.now() > until) return stopWaiting()
      latestListen()
        .then((listen) => {
          if (!poll || !isNewListen(seen, listen)) return
          setLatest(listen)
          setHeard(listen)
          stopWaiting()
        })
        .catch(() => {
          // A missed check is retried on the next tick.
        })
    }, FIRST_LISTEN_POLL_MS)
  }

  async function connect() {
    setBusy(true)
    setProblem(null)
    try {
      const seen = await latestListen()
      setLatest(seen)
      setFresh(await connectScrobbler({ data: { scrobbler: choice() } }))
      setScrobblers(await listScrobblers())
      waitForFirstListen(seen)
    } catch (error) {
      fail(error, 'The scrobbler could not be connected.')
    } finally {
      setBusy(false)
    }
  }

  function done() {
    stopWaiting()
    setFresh(null)
    setHeard(null)
  }

  async function revoke(token: AgentToken) {
    setProblem(null)
    setRevoking(true)
    try {
      await revokeScrobbler({ data: { id: token.id } })
      if (fresh()?.token.id === token.id) done()
      setScrobblers(scrobblers().filter((s) => s.id !== token.id))
    } catch (error) {
      fail(error, 'That scrobbler was not disconnected.')
    } finally {
      setRevoking(false)
      setPending(null)
    }
  }

  return (
    <section class={cn(cardClass, 'mt-10 p-5')}>
      <h2 class="font-display text-xl font-medium">Music</h2>
      <p class="mt-2 max-w-[60ch] text-sm text-muted">
        Plays on YouTube, YouTube Music, Spotify and Apple Music in a browser,
        or any app on Android, land in your listening log. The Spotify and Apple
        Music apps on iPhone can’t send plays.
      </p>

      <Show when={latest()}>
        {(listen) => (
          <p class="mt-4 text-sm">
            <span class="text-muted">Last listen: </span>
            <span class="font-medium">{listenTitle(listen())}</span>
            <span class="block text-xs text-muted">
              {listenDetail(listen())}
            </span>
            <Link
              to="/app/music"
              class="mt-1 inline-block font-semibold text-accent hover:underline"
            >
              All listening ›
            </Link>
          </p>
        )}
      </Show>

      <Show
        when={fresh()}
        fallback={
          <div class="mt-4 flex flex-col gap-3">
            <RadioGroup
              aria-label="Scrobbler"
              class="flex flex-wrap gap-2"
              value={choice()}
              onChange={(next) => setChoice(next as Scrobbler)}
            >
              <For each={SCROBBLERS}>
                {(option) => (
                  <RadioGroupItem value={option}>
                    {scrobblerLabel(option)}
                  </RadioGroupItem>
                )}
              </For>
            </RadioGroup>
            <p class="max-w-[60ch] text-sm">{scrobblerSummary(choice())}</p>
            <Button
              variant="primary"
              class="self-start"
              disabled={busy()}
              onClick={() => void connect()}
            >
              {busy() ? 'Connecting…' : `Connect ${scrobblerLabel(choice())}`}
            </Button>
          </div>
        }
      >
        {(connection) => (
          <div class="mt-4 flex flex-col gap-4 rounded-panel border border-line p-4">
            <SetupSteps setup={connection().music} />
            <p class="text-xs text-muted">
              The token is shown only now and works like a password: anyone with
              it can add listens to your log. Disconnect it if you shared it by
              mistake.
            </p>
            <FirstListen waiting={waiting()} heard={heard()} />
            <Button class="self-start" onClick={done}>
              Done
            </Button>
          </div>
        )}
      </Show>

      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>

      <Show when={scrobblers().length > 0}>
        <ul class="mt-4 divide-y divide-line">
          <For each={scrobblers()}>
            {(token) => (
              <li class="flex items-center justify-between gap-4 py-3">
                <span class="min-w-0">
                  <span class="block truncate font-medium">{token.name}</span>
                  <span class="block text-xs text-muted">
                    {lastUsedLabel(token)}
                  </span>
                </span>
                <Button
                  variant="danger-outline"
                  size="sm"
                  class="shrink-0"
                  onClick={() => setPending(token)}
                >
                  Disconnect
                </Button>
              </li>
            )}
          </For>
        </ul>
      </Show>
      <AlertDialog
        open={pending() !== null}
        title={`Disconnect ${asked()?.name ?? ''}?`}
        description="It stops sending listens at once. Listens already in your log stay."
        confirmLabel="Disconnect"
        busy={revoking()}
        onConfirm={() => {
          const token = pending()
          if (token) void revoke(token)
        }}
        onCancel={() => setPending(null)}
      />
    </section>
  )
}

function SetupSteps(props: { setup: MusicSetup }) {
  return (
    <ol class="flex list-decimal flex-col gap-3 pl-5 text-sm">
      <For each={props.setup.steps}>
        {(step) => (
          <li class="flex flex-col gap-2">
            <span>{step.text}</span>
            <Show when={step.link}>
              {(link) => (
                <a
                  href={link().url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class={cn(buttonVariants({ size: 'sm' }), 'self-start')}
                >
                  {link().label}
                </a>
              )}
            </Show>
            <Show when={step.fields?.length}>
              <dl class="flex flex-col gap-2">
                <For each={step.fields}>
                  {(field) => (
                    <CopyField
                      label={field.label}
                      value={field.value}
                      secret={field.secret}
                    />
                  )}
                </For>
              </dl>
            </Show>
          </li>
        )}
      </For>
    </ol>
  )
}

/** One value to paste into the scrobbler. The token stays masked; Copy takes it whole. */
function CopyField(props: { label: string; value: string; secret?: boolean }) {
  const [copied, setCopied] = createSignal(false)
  const shown = () =>
    props.secret
      ? `${props.value.slice(0, 8)}••••••${props.value.slice(-3)}`
      : props.value
  async function copy() {
    try {
      await navigator.clipboard.writeText(props.value)
      setCopied(true)
      // The label change is silent to a screen reader; the toast is announced.
      showToast(`${props.label} copied.`)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      showToast('Copying failed. Select it and copy it yourself.')
    }
  }
  return (
    <div class="flex items-center gap-3 rounded-field bg-paper p-2 pl-3">
      <dt class="w-20 shrink-0 text-xs text-muted">{props.label}</dt>
      <dd class="min-w-0 flex-1 break-all font-mono text-xs">{shown()}</dd>
      <button
        type="button"
        class="shrink-0 rounded-full border border-ink/25 bg-surface px-3 py-1 text-xs font-semibold"
        onClick={() => void copy()}
      >
        {copied() ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}

function FirstListen(props: { waiting: boolean; heard: Listen | null }) {
  return (
    <div role="status" class="text-sm">
      <Show
        when={props.heard}
        fallback={
          <Show
            when={props.waiting}
            fallback={
              <span class="text-muted">
                No listen yet. Play a song, then check the scrobbler’s settings
                if nothing shows up here.
              </span>
            }
          >
            <span class="text-muted">Waiting for your first listen…</span>
          </Show>
        }
      >
        {(listen) => (
          <span>
            <span class="font-medium text-accent">
              ✓ Got it: {listenTitle(listen())}
            </span>
            <span class="block text-xs text-muted">
              {listenDetail(listen())}
            </span>
          </span>
        )}
      </Show>
    </div>
  )
}
