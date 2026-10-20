import { For, Show, createSignal } from 'solid-js'
import { canChangeLibrary, lastUsedLabel } from '../lib/stremio/model'
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
    try {
      await revokeStremio({ data: { id: token.id } })
      if (fresh()?.token.id === token.id) setFresh(null)
      setLinks(links().filter((link) => link.id !== token.id))
    } catch (error) {
      fail(error, 'That Stremio link was not revoked.')
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
    <section class="mt-10 rounded-[20px] bg-surface p-5">
      <h2 class="font-display text-xl font-medium">Stremio</h2>
      <p class="mt-2 max-w-[60ch] text-sm text-muted">
        Your Continue watching, Next 7 days and Plan to watch appear as rows in
        Stremio. Finishing an episode there ticks it here, and every change
        shows in your history with an undo. Works with Stremio Web and Stremio 5
        on desktop.
      </p>

      <Show
        when={fresh()}
        fallback={
          <div class="mt-4 flex flex-col gap-3">
            <label class="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                class="mt-0.5"
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
            <button
              type="button"
              class="min-h-11 self-start rounded-full border border-ink/25 px-5 text-sm font-semibold disabled:opacity-50"
              disabled={busy()}
              onClick={() => void connect()}
            >
              {busy() ? 'Connecting…' : 'Connect Stremio'}
            </button>
          </div>
        }
      >
        {(connection) => (
          <div class="mt-4 flex flex-col gap-3 rounded-[14px] border border-line p-4">
            <p class="text-sm font-medium">
              Anyone with this link can see your library and mark things
              watched. Treat it like a password; it is shown only now.
            </p>
            <div class="flex flex-wrap gap-2">
              <a
                href={connection().stremio.installUrl}
                class="min-h-11 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-on-accent"
              >
                Open in Stremio
              </a>
              <a
                href={connection().stremio.webInstallUrl}
                target="_blank"
                rel="noopener noreferrer"
                class="min-h-11 rounded-full border border-ink/25 px-5 py-2.5 text-sm font-semibold"
              >
                Install on Stremio Web
              </a>
              <button
                type="button"
                class="min-h-11 rounded-full border border-ink/25 px-5 text-sm font-semibold"
                onClick={() => void copy(connection().stremio.manifestUrl)}
              >
                {copied() ? 'Copied' : 'Copy link'}
              </button>
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
                <button
                  type="button"
                  class="shrink-0 rounded-full border border-danger/50 px-4 py-1.5 text-sm font-semibold text-danger"
                  onClick={() => void revoke(link)}
                >
                  Revoke
                </button>
              </li>
            )}
          </For>
        </ul>
      </Show>
    </section>
  )
}
