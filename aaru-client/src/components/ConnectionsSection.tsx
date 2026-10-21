import { For, Show, createMemo, createResource, createSignal } from 'solid-js'
import { AGENT_KINDS, accessLabel, kindLabel } from '../lib/agents/model'
import type { AgentKind } from '../lib/agents/model'
import { lastUsedLabel } from '../lib/stremio/model'
import { cn } from '../lib/cn'
import { AlertDialog } from './ui/alert-dialog'
import { Button, buttonVariants } from './ui/button'
import { EXTENSION_STORES } from '../lib/agents/extension'
import { RadioGroup, RadioGroupItem } from './ui/radio-group'
import { showToast } from './ui/toast'
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

/** The browser extension (SCR-007) is one more choice; it connects from the extension itself. */
type Choice = AgentKind | 'browser'
const CHOICES: readonly Choice[] = [...AGENT_KINDS, 'browser']

// OUT-004: connect an AI agent to Aaru over MCP. The token is shown once, inside the steps
// it fills in, right after creating it. SCR-007's browser extension is listed here too.
export function ConnectionsSection(props: { connections: AgentToken[] }) {
  const [connections, setConnections] = createSignal(props.connections)
  const [choice, setChoice] = createSignal<Choice>('claude')
  // The MCP client picked, or null for the browser extension.
  const kind = () => {
    const picked = choice()
    return picked === 'browser' ? null : picked
  }
  const [name, setName] = createSignal('')
  const [allowWrites, setAllowWrites] = createSignal(false)
  const [allowImports, setAllowImports] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [fresh, setFresh] = createSignal<AgentConnection | null>(null)
  const [pending, setPending] = createSignal<AgentToken | null>(null)
  const [revoking, setRevoking] = createSignal(false)
  // The last token asked about, so the dialog keeps its title while it fades out.
  const asked = createMemo<AgentToken | null>((last) => pending() ?? last, null)
  const [preview] = createResource(kind, (k) => getSetup({ data: { kind: k } }))
  const mcpKind = () => kind() ?? 'claude'

  const fail = (error: unknown, fallback: string) =>
    setProblem(error instanceof Error ? error.message : fallback)

  async function create() {
    setBusy(true)
    setProblem(null)
    try {
      setFresh(
        await createConnection({
          data: {
            kind: mcpKind(),
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
    setRevoking(true)
    try {
      await revokeConnection({ data: { id: token.id } })
      if (fresh()?.token.id === token.id) setFresh(null)
      setConnections(connections().filter((c) => c.id !== token.id))
    } catch (error) {
      fail(error, 'That connection was not revoked.')
    } finally {
      setRevoking(false)
      setPending(null)
    }
  }

  return (
    <section class={cn(cardClass, 'mt-10 p-5')}>
      <h2 class="font-display text-xl font-medium">Connections</h2>
      <p class="mt-2 max-w-[60ch] text-sm text-muted">
        Let an AI agent read your library over MCP: what you are watching, what
        airs this week, what to add. If you allow changes, it can change one
        item at a time, and every change shows in your history with an undo. The
        browser extension marks what you finish on streaming sites.
      </p>

      <Show
        when={fresh()}
        fallback={
          <div class="mt-4 flex flex-col gap-4">
            <RadioGroup
              aria-label="Agent"
              class="flex flex-wrap gap-2"
              value={choice()}
              onChange={(next) => setChoice(next as Choice)}
            >
              <For each={CHOICES}>
                {(option) => (
                  <RadioGroupItem value={option}>
                    {kindLabel(option)}
                  </RadioGroupItem>
                )}
              </For>
            </RadioGroup>

            <Show when={kind()} fallback={<ExtensionSteps />}>
              <Show when={preview()}>
                {(setup) => <SetupSteps setup={setup()} />}
              </Show>
            </Show>

            <Show when={kind() && preview()?.auth === 'token'}>
              <label class="flex flex-col gap-1 text-sm">
                <span class="font-medium">Name</span>
                <input
                  type="text"
                  maxLength={80}
                  placeholder={kindLabel(mcpKind())}
                  class="min-h-11 max-w-sm rounded-field border border-line bg-paper px-3"
                  value={name()}
                  onInput={(e) => setName(e.currentTarget.value)}
                />
              </label>
              <label class="flex items-start gap-2 text-sm">
                <input
                  type="checkbox"
                  class="mt-0.5 accent-accent"
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
                {busy() ? 'Creating…' : `Connect ${kindLabel(mcpKind())}`}
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
                <Button
                  variant="danger-outline"
                  size="sm"
                  class="shrink-0"
                  onClick={() => setPending(token)}
                >
                  Revoke
                </Button>
              </li>
            )}
          </For>
        </ul>
      </Show>
      <AlertDialog
        open={pending() !== null}
        title={`Revoke ${asked()?.name ?? ''}?`}
        description="Anything using it stops working at once."
        confirmLabel="Revoke"
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

/** SCR-007: the extension connects itself; Settings only says how. */
function ExtensionSteps() {
  return (
    <div class="flex flex-col gap-3">
      <p class="max-w-[60ch] text-sm">
        Finish an episode or a film on Netflix, Disney+ or Prime Video in your
        browser and it is marked watched here. The extension can’t read your
        library.
      </p>
      <ol class="flex list-decimal flex-col gap-1 pl-5 text-sm">
        <li>Install Aaru for Chrome or Firefox.</li>
        <li>Click Aaru in the toolbar, then Connect.</li>
        <li>Approve on the page it opens.</li>
      </ol>
      <Show
        when={EXTENSION_STORES.length > 0}
        fallback={
          <p class="text-xs text-muted">
            Not in the Chrome Web Store or Firefox Add-ons yet.
          </p>
        }
      >
        <div class="flex flex-wrap gap-2">
          <For each={EXTENSION_STORES}>
            {(store) => (
              <a
                href={store.href}
                target="_blank"
                rel="noopener noreferrer"
                class={buttonVariants()}
              >
                {store.label}
              </a>
            )}
          </For>
        </div>
      </Show>
    </div>
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
      // The label change is silent to a screen reader; the toast is announced.
      showToast('Copied to the clipboard.')
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
