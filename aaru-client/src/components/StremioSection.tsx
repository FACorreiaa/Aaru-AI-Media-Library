import { For, Show, createSignal } from 'solid-js'
import { canChangeLibrary, lastUsedLabel } from '../lib/stremio/model'
import { StremioHistoryImport } from './StremioHistoryImport'
import { AlertDialog } from './ui/alert-dialog'
import { Button, buttonVariants } from './ui/button'
import { Card } from './ui/card'
import {
  connectStremio,
  listStremio,
  revokeStremio,
} from '../lib/stremio/server'
import type { AgentToken, StremioConnection } from '../lib/stremio/server'

// SCR-003: install Aaru's addon in Stremio. The install links carry the secret, so they are
// shown once, right after connecting, and never again.
export function StremioSection(props: { links: AgentToken[] }) {
  const [links, setLinks] = createSignal(props.links)
  const [allowWrites, setAllowWrites] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const [fresh, setFresh] = createSignal<StremioConnection | null>(null)
  const [copied, setCopied] = createSignal(false)
  const [pending, setPending] = createSignal<AgentToken | null>(null)
  const [revoking, setRevoking] = createSignal(false)

  const fail = (error: unknown, fallback: string) =>
    setProblem(error instanceof Error ? error.message : fallback)

  async function connect() {
    setBusy(true)
    setProblem(null)
    setCopied(false)
    try {
      setFresh(
        await connectStremio({ data: { allowLibraryWrites: allowWrites() } }),
      )
      setLinks(await listStremio())
    } catch (error) {
      fail(error, 'Stremio could not be connected.')
    } finally {
      setBusy(false)
    }
  }

  async function revoke(token: AgentToken) {
    setProblem(null)
    setRevoking(true)
    try {
      await revokeStremio({ data: { id: token.id } })
      if (fresh()?.token.id === token.id) setFresh(null)
      setLinks(links().filter((link) => link.id !== token.id))
    } catch (error) {
      fail(error, 'That Stremio link was not revoked.')
    } finally {
      setRevoking(false)
      setPending(null)
    }
  }

  async function copy(url: string) {
    try {
      await navigator.clipboard.writeText(url)
      setCopied(true)
    } catch {
      setProblem('Copying failed. Select the link and copy it yourself.')
    }
  }

  return (
    <Card class="mt-10 p-5">
      <h2 class="font-display text-xl font-medium">Stremio</h2>
      <p class="mt-2 max-w-[60ch] text-sm text-muted">
        Your Continue watching, Next 7 days and Plan to watch appear as rows in
        Stremio. Finishing an episode there ticks it here, and every change
        shows in your history with an undo. Works with Stremio Web and Stremio 5
        on desktop.
      </p>

      <StremioGuide />

      <Show
        when={fresh()}
        fallback={
          <div class="mt-4 flex flex-col gap-3">
            <label class="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                class="mt-0.5 accent-accent"
                checked={allowWrites()}
                onChange={(e) => setAllowWrites(e.currentTarget.checked)}
              />
              <span>
                Also let Stremio add titles and unmark episodes.
                <span class="block text-xs text-muted">
                  Removing a title in Stremio never removes it from Aaru.
                </span>
              </span>
            </label>
            <Button
              class="self-start"
              disabled={busy()}
              onClick={() => void connect()}
            >
              {busy() ? 'Connecting…' : 'Connect Stremio'}
            </Button>
          </div>
        }
      >
        {(connection) => (
          <div class="mt-4 flex flex-col gap-3 rounded-panel border border-line p-4">
            <p class="text-sm font-medium">
              Anyone with this link can see your library and mark things
              watched. Treat it like a password; it is shown only now.
            </p>
            <div class="flex flex-wrap gap-2">
              <a
                href={connection().stremio.installUrl}
                class={buttonVariants({ variant: 'primary' })}
              >
                Open in Stremio
              </a>
              <a
                href={connection().stremio.webInstallUrl}
                target="_blank"
                rel="noopener noreferrer"
                class={buttonVariants()}
              >
                Install on Stremio Web
              </a>
              <Button
                onClick={() => void copy(connection().stremio.manifestUrl)}
              >
                {copied() ? 'Copied' : 'Copy link'}
              </Button>
            </div>
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

      <Show when={links().length > 0}>
        <ul class="mt-4 divide-y divide-line">
          <For each={links()}>
            {(link) => (
              <li class="flex items-center justify-between gap-4 py-3">
                <span class="min-w-0">
                  <span class="block truncate font-medium">{link.name}</span>
                  <span class="block text-xs text-muted">
                    {lastUsedLabel(link)}
                    {canChangeLibrary(link) ? ' · can add titles' : ''}
                  </span>
                </span>
                <Button
                  variant="danger-outline"
                  size="sm"
                  class="shrink-0"
                  onClick={() => setPending(link)}
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
        title="Revoke this Stremio link?"
        description="Stremio stops showing your Aaru library."
        confirmLabel="Revoke"
        busy={revoking()}
        onConfirm={() => {
          const token = pending()
          if (token) void revoke(token)
        }}
        onCancel={() => setPending(null)}
      />

      <StremioHistoryImport />
    </Card>
  )
}

const setupSteps = [
  'Choose whether Stremio may also add titles and unmark episodes, then press Connect Stremio.',
  'Press Open in Stremio for the desktop app or Install on Stremio Web in a browser. Or copy the link and paste it into the search box on Stremio’s Addons page.',
  'Approve the install in Stremio. Your rows appear on Stremio’s board and load as you scroll to them.',
]

const behaviour = [
  'Marking an episode or film watched in Stremio ticks it here. It shows in your history with an undo.',
  'Finishing an episode in Stremio’s player ticks it too.',
  'Unmarking and adding titles reach Aaru only if you allowed it when connecting. Removing a title in Stremio never removes it here.',
  'Aaru adds no streams. You play things with the add-ons you already use.',
  'What you tick in Aaru does not show as watched in Stremio.',
  'Works with Stremio Web and Stremio 5 on desktop. The phone and TV apps are not confirmed yet.',
]

// The setup steps, so nobody has to leave the app to learn how the addon works.
function StremioGuide() {
  return (
    <details class="group mt-4 rounded-panel border border-line">
      <summary class="flex cursor-pointer list-none items-center justify-between gap-4 px-4 py-3 text-sm font-semibold [&::-webkit-details-marker]:hidden">
        How to set it up
        <span
          aria-hidden="true"
          class="text-lg leading-none text-muted transition-transform group-open:rotate-45"
        >
          +
        </span>
      </summary>
      <div class="max-w-[60ch] px-4 pb-4 text-sm text-muted">
        <ol class="list-decimal space-y-1.5 pl-5">
          <For each={setupSteps}>{(step) => <li>{step}</li>}</For>
        </ol>
        <h3 class="mt-4 font-semibold text-ink">What it does</h3>
        <ul class="mt-1.5 list-disc space-y-1.5 pl-5">
          <For each={behaviour}>{(line) => <li>{line}</li>}</For>
        </ul>
        <h3 class="mt-4 font-semibold text-ink">History and lost links</h3>
        <p class="mt-1.5">
          Import my Stremio history brings in what you watched before, once:
          approve the code on stremio.com, then review the import before
          anything changes. The install link is shown only once. If you lose it,
          revoke it and connect again.
        </p>
      </div>
    </details>
  )
}
