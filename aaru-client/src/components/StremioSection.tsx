import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { canChangeLibrary, lastUsedLabel } from '../lib/stremio/model'
import {
  Button,
  buttonVariants,
  Checkbox,
  CheckboxControl,
  CheckboxDescription,
  CheckboxInput,
  CheckboxLabel,
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '~/components/ui'
import { ConfirmDialog } from './ConfirmDialog'
import { SettingsSection } from './settings/SettingsSection'
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
      fail(error, 'Stremio was not disconnected.')
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
    <SettingsSection
      id="stremio"
      title="Stremio"
      description="Your Continue watching, Next 7 days and Plan to watch appear as rows in Stremio. Finishing an episode there ticks it here, and every change shows in your history with an undo. Works with Stremio Web and Stremio 5 on desktop."
      footer={
        <>
          What you watched before connecting comes in once, from{' '}
          <Link
            to="/app/settings/import"
            hash="stremio"
            class="font-semibold text-accent hover:underline"
          >
            Import your Stremio history
          </Link>
          .
        </>
      }
    >
      <StremioGuide />

      <Show
        when={fresh()}
        fallback={
          <div class="mt-4 flex flex-col gap-3">
            <Checkbox
              class="flex items-start gap-2.5"
              checked={allowWrites()}
              onChange={setAllowWrites}
            >
              <CheckboxInput />
              <CheckboxControl class="mt-0.5" />
              <span class="flex flex-col gap-1">
                <CheckboxLabel class="cursor-pointer leading-snug font-normal">
                  Also let Stremio add titles and unmark episodes.
                </CheckboxLabel>
                <CheckboxDescription class="text-xs text-muted">
                  Removing a title in Stremio never removes it from Aaru.
                </CheckboxDescription>
              </span>
            </Checkbox>
            <Button
              variant="outline"
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
                class={buttonVariants({ variant: 'default' })}
              >
                Open in Stremio
              </a>
              <a
                href={connection().stremio.webInstallUrl}
                target="_blank"
                rel="noopener noreferrer"
                class={buttonVariants({ variant: 'outline' })}
              >
                Install on Stremio Web
              </a>
              <Button
                variant="outline"
                onClick={() => void copy(connection().stremio.manifestUrl)}
              >
                {copied() ? 'Copied' : 'Copy link'}
              </Button>
            </div>
            <Button
              variant="link"
              size="bare"
              class="self-start text-sm font-semibold text-accent"
              onClick={() => setFresh(null)}
            >
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
                  Disconnect
                </Button>
              </li>
            )}
          </For>
        </ul>
      </Show>
      <ConfirmDialog
        open={pending() !== null}
        title="Disconnect Stremio?"
        description="Stremio can no longer reach your library, and its Aaru rows go."
        confirmLabel="Disconnect"
        busy={revoking()}
        onConfirm={() => {
          const token = pending()
          if (token) void revoke(token)
        }}
        onCancel={() => setPending(null)}
      />
    </SettingsSection>
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
    <Collapsible class="group rounded-panel border border-line">
      <CollapsibleTrigger class="flex w-full cursor-pointer items-center justify-between gap-4 rounded-panel px-4 py-3 text-left text-sm font-semibold">
        How to set it up
        <span
          aria-hidden="true"
          class="text-lg leading-none text-muted transition-transform group-data-[expanded]:rotate-45"
        >
          +
        </span>
      </CollapsibleTrigger>
      <CollapsibleContent class="max-w-prose px-4 pb-4 text-sm text-muted">
        <ol class="list-decimal space-y-1.5 pl-5">
          <For each={setupSteps}>{(step) => <li>{step}</li>}</For>
        </ol>
        <h3 class="mt-4 font-semibold text-ink">What it does</h3>
        <ul class="mt-1.5 list-disc space-y-1.5 pl-5">
          <For each={behaviour}>{(line) => <li>{line}</li>}</For>
        </ul>
        <h3 class="mt-4 font-semibold text-ink">History and lost links</h3>
        <p class="mt-1.5">
          Import your Stremio history, in Settings → Import, brings in what you
          watched before, once: approve the code on stremio.com, then review the
          import before anything changes. The install link is shown only once.
          If you lose it, disconnect and connect again.
        </p>
      </CollapsibleContent>
    </Collapsible>
  )
}
