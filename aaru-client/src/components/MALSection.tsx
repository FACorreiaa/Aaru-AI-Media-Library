import { Show, createSignal } from 'solid-js'
import { malConnectedLabel } from '../lib/mal/model'
import { connectMAL, disconnectMAL } from '../lib/mal/server'
import type { MALConnection } from '../lib/mal/server'
import { Alert, AlertDescription, Button } from '~/components/ui'
import { ConfirmDialog } from './ConfirmDialog'
import { SettingsSection } from './settings/SettingsSection'

const FACTS = [
  'Status, watched episodes and score, one MyAnimeList entry per season.',
  'Only changes from now on. Your MyAnimeList list is not overwritten.',
  'Removing an anime here leaves it on MyAnimeList.',
]

// SCR-005: each user connects their own MyAnimeList account (PKCE, tokens kept sealed by the
// server). From then on the server pushes anime progress; this section only connects and
// disconnects, and says so when MAL stopped accepting Aaru.
export function MALSection(props: {
  connection: MALConnection
  /** Where MAL sends the browser back: this page. */
  returnTo: () => string
}) {
  const [connection, setConnection] = createSignal(props.connection)
  const [busy, setBusy] = createSignal<'connect' | 'disconnect'>()
  const [confirming, setConfirming] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function connect() {
    setBusy('connect')
    setProblem(null)
    try {
      // Leaves the page; MAL brings the browser back with `?mal=`.
      window.location.assign(
        await connectMAL({ data: { returnTo: props.returnTo() } }),
      )
      return
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'MyAnimeList could not be reached.',
      )
    }
    setBusy(undefined)
  }

  async function disconnect() {
    setBusy('disconnect')
    setProblem(null)
    try {
      await disconnectMAL()
      setConnection({ connected: false, needsReconnect: false })
    } catch (error) {
      setProblem(
        error instanceof Error
          ? error.message
          : 'MyAnimeList was not disconnected.',
      )
    }
    setBusy(undefined)
    setConfirming(false)
  }

  return (
    <SettingsSection
      id="myanimelist"
      title="MyAnimeList"
      description="Anime you update in Aaru update your MyAnimeList list too."
    >
      <ul class="flex list-disc flex-col gap-1 pl-5 text-sm text-muted">
        {FACTS.map((fact) => (
          <li>{fact}</li>
        ))}
      </ul>

      <Show
        when={connection().connected}
        fallback={
          <Button
            variant="outline"
            class="self-start"
            disabled={busy() !== undefined}
            onClick={() => void connect()}
          >
            {busy() === 'connect'
              ? 'Opening MyAnimeList…'
              : 'Connect MyAnimeList'}
          </Button>
        }
      >
        <Show
          when={connection().needsReconnect}
          fallback={
            <div class="flex flex-wrap items-center justify-between gap-3">
              <span class="text-sm">{malConnectedLabel(connection())}</span>
              <Button
                variant="link"
                size="bare"
                class="text-sm font-semibold text-accent"
                disabled={busy() !== undefined}
                onClick={() => setConfirming(true)}
              >
                Disconnect
              </Button>
            </div>
          }
        >
          <Alert variant="destructive">
            <AlertDescription>
              MyAnimeList stopped accepting Aaru. Nothing is sent until you
              reconnect.
            </AlertDescription>
          </Alert>
          <Button
            variant="outline"
            class="self-start"
            disabled={busy() !== undefined}
            onClick={() => void connect()}
          >
            {busy() === 'connect' ? 'Opening MyAnimeList…' : 'Reconnect'}
          </Button>
        </Show>
      </Show>

      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>

      <ConfirmDialog
        open={confirming()}
        title="Disconnect MyAnimeList?"
        description="Aaru stops updating your MyAnimeList list. Both lists stay as they are."
        confirmLabel="Disconnect"
        busy={busy() === 'disconnect'}
        onConfirm={() => void disconnect()}
        onCancel={() => setConfirming(false)}
      />
    </SettingsSection>
  )
}
