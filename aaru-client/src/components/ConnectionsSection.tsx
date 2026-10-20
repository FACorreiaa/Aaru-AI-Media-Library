import { For, Show, createResource, createSignal } from 'solid-js'
import { AGENT_KINDS, accessLabel, kindLabel } from '../lib/agents/model'
import type { AgentKind } from '../lib/agents/model'
import { lastUsedLabel } from '../lib/stremio/model'
import { cn } from '../lib/cn'
import { Button } from './ui/button'
import { cardClass } from './ui/card'
import {
  createConnection,
  getSetup,
  listConnections,
  revokeConnection,
} from '../lib/agents/server'
import type {
  AgentConnection,
  AgentSetup,
  AgentToken,
} from '../lib/agents/server'

// OUT-004: connect an AI agent to Aaru over MCP. The token is shown once, inside the steps
// it fills in, right after creating it.
export function ConnectionsSection(props: { connections: AgentToken[] }) {
  const [connections, setConnections] = createSignal(props.connections)
  const [kind, setKind] = createSignal<AgentKind>('claude')
  const [name, setName] = createSignal('')
  const [allowWrites, setAllowWrites] = createSignal(false)
  const [allowImports, setAllowImports] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [fresh, setFresh] = createSignal<AgentConnection | null>(null)
  const [confirming, setConfirming] = createSignal<string | null>(null)
  const [preview] = createResource(kind, (k) => getSetup({ data: { kind: k } }))

  const fail = (error: unknown, fallback: string) =>
    setProblem(error instanceof Error ? error.message : fallback)

  async function create() {
    setBusy(true)
    setProblem(null)
    try {
      setFresh(
        await createConnection({
          data: {
            kind: kind(),
            name: name() || undefined,
            allowLibraryWrites: allowWrites(),
            allowImports: allowImports(),
          },
        }),
      )
      setName('')
      setConnections(await listConnections())
    } catch (error) {
      fail(error, 'The connection could not be created.')
    } finally {
      setBusy(false)
    }
  }

  async function revoke(token: AgentToken) {
    setProblem(null)
    try {
      await revokeConnection({ data: { id: token.id } })
      if (fresh()?.token.id === token.id) setFresh(null)
      setConfirming(null)
      setConnections(connections().filter((c) => c.id !== token.id))
    } catch (error) {
      fail(error, 'That connection was not revoked.')
    }
  }

  return (
    <section class={cn(cardClass, 'mt-10 p-5')}>
      <h2 class="font-display text-xl font-medium">Connections</h2>
      <p class="mt-2 max-w-[60ch] text-sm text-muted">
        Let an AI agent read your library over MCP: what you are watching, what
        airs this week, what to add. If you allow changes, it can change one
        item at a time, and every change shows in your history with an undo.
      </p>

      <Show
        when={fresh()}
        fallback={
          <div class="mt-4 flex flex-col gap-4">
            <div
              role="radiogroup"
              aria-label="Agent"
              class="flex flex-wrap gap-2"
            >
              <For each={AGENT_KINDS}>
                {(option) => (
                  <button
                    type="button"
                    role="radio"
                    aria-checked={kind() === option}
                    class="min-h-11 rounded-full border px-4 text-sm font-semibold"
                    classList={{
                      'border-accent bg-accent text-on-accent':
                        kind() === option,
                      'border-ink/25': kind() !== option,
                    }}
                    onClick={() => setKind(option)}
                  >
                    {kindLabel(option)}
                  </button>
                )}
              </For>
            </div>

            <Show when={preview()}>
              {(setup) => <SetupSteps setup={setup()} />}
            </Show>

            <Show when={preview()?.auth === 'token'}>
              <label class="flex flex-col gap-1 text-sm">
                <span class="font-medium">Name</span>
                <input
                  type="text"
                  maxLength={80}
                  placeholder={kindLabel(kind())}
                  class="min-h-11 max-w-sm rounded-field border border-line bg-paper px-3"
                  value={name()}
                  onInput={(e) => setName(e.currentTarget.value)}
                />
              </label>
              <label class="flex items-start gap-2 text-sm">
                <input
                  type="checkbox"
                  class="mt-0.5"
                  checked={allowWrites()}
                  onChange={(e) => setAllowWrites(e.currentTarget.checked)}
                />
                <span>
                  Allow changes
                  <span class="block text-xs text-muted">
                    One item at a time, as a tap would. It can never remove
                    anything or change many items at once.
                  </span>
                </span>
              </label>
              <label class="flex items-start gap-2 text-sm">
                <input
                  type="checkbox"
                  class="mt-0.5"
                  checked={allowImports()}
                  onChange={(e) => setAllowImports(e.currentTarget.checked)}
                />
                <span>
                  Allow imports
                  <span class="block text-xs text-muted">
                    It can hand Aaru a list (IMDb, Letterboxd, Goodreads,
                    MyAnimeList, any CSV). You review the import here before
                    anything is added.
                  </span>
                </span>
              </label>
              <Button
                variant="primary"
                class="self-start"
                disabled={busy()}
                onClick={() => void create()}
              >
                {busy() ? 'Creating…' : `Connect ${kindLabel(kind())}`}
              </Button>
            </Show>
          </div>
        }
      >
        {(connection) => (
          <div class="mt-4 flex flex-col gap-3 rounded-panel border border-line p-4">
            <p class="text-sm font-medium">
              Your token is in the steps below. Anyone with it can read your
              library, so treat it like a password; it is shown only now.
            </p>
            <Show when={connection().setup}>
              {(setup) => <SetupSteps setup={setup()} />}
            </Show>
            <button
              type="button"
              class="self-start text-sm font-semibold text-accent hover:underline"
              onClick={() => setFresh(null)}
            >
              Done
            </button>
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

      <Show when={connections().length > 0}>
        <ul class="mt-4 divide-y divide-line">
          <For each={connections()}>
            {(token) => (
              <li class="flex items-center justify-between gap-4 py-3">
                <span class="min-w-0">
                  <span class="block truncate font-medium">{token.name}</span>
                  <span class="block text-xs text-muted">
                    {kindLabel(token.kind)} · {accessLabel(token)} ·{' '}
                    {lastUsedLabel(token)}
                  </span>
                </span>
                <Show
                  when={confirming() === token.id}
                  fallback={
                    <Button
                      variant="danger-outline"
                      size="sm"
                      class="shrink-0"
                      onClick={() => setConfirming(token.id)}
                    >
                      Revoke
                    </Button>
                  }
                >
                  <span class="flex shrink-0 gap-2">
                    <Button
                      variant="danger"
                      size="sm"
                      onClick={() => void revoke(token)}
                    >
                      Revoke now
                    </Button>
                    <Button size="sm" onClick={() => setConfirming(null)}>
                      Keep
                    </Button>
                  </span>
                </Show>
              </li>
            )}
          </For>
        </ul>
      </Show>
    </section>
  )
}

function SetupSteps(props: { setup: AgentSetup }) {
  return (
    <ol class="flex flex-col gap-3">
      <For each={props.setup.steps}>
        {(step) => (
          <li class="flex flex-col gap-1">
            <span class="text-sm font-medium">{step.label}</span>
            <CopyBlock text={step.text} />
            <Show when={step.note}>
              {(note) => <span class="text-xs text-muted">{note()}</span>}
            </Show>
          </li>
        )}
      </For>
      <li class="flex flex-col gap-1">
        <span class="text-sm font-medium">Then ask your agent</span>
        <CopyBlock text={props.setup.prompt} wrap />
      </li>
    </ol>
  )
}

function CopyBlock(props: { text: string; wrap?: boolean }) {
  const [copied, setCopied] = createSignal(false)
  async function copy() {
    try {
      await navigator.clipboard.writeText(props.text)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // Clipboard can be blocked; the text stays selectable.
    }
  }
  return (
    <div class="relative rounded-field bg-paper">
      <pre
        class="overflow-x-auto p-3 pr-20 font-mono text-xs"
        classList={{ 'whitespace-pre-wrap': props.wrap }}
      >
        {props.text}
      </pre>
      <button
        type="button"
        class="absolute right-2 top-2 rounded-full border border-ink/25 bg-surface px-3 py-1 text-xs font-semibold"
        onClick={() => void copy()}
      >
        {copied() ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}
