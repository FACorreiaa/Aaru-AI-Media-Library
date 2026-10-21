import { useNavigate } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import {
  connectTrakt,
  disconnectTrakt,
  startTraktImport,
} from '../lib/imports/server'
import type { TraktConnection } from '../lib/imports/server'
import { TRAKT_NOTICE } from '../lib/credits'
import { Button } from './ui/button'

// IMP-002/003: each user connects their own Trakt account (PKCE, tokens kept sealed by the
// server), then imports it like any other source: matched, planned, approved. Importing again
// only fills gaps and moves statuses forward. Aaru never writes to Trakt from here.
export function TraktImport(props: {
  connection: TraktConnection
  /** Where Trakt sends the browser back, e.g. this page. */
  returnTo: () => string
  onDisconnected: () => void
}) {
  const navigate = useNavigate()
  const [busy, setBusy] = createSignal<'connect' | 'import' | 'disconnect'>()
  const [problem, setProblem] = createSignal<string | null>(null)

  async function run(kind: 'connect' | 'import' | 'disconnect') {
    setBusy(kind)
    setProblem(null)
    try {
      if (kind === 'connect') {
        // Leaves the page; Trakt brings the browser back with `?trakt=`.
        window.location.assign(
          await connectTrakt({ data: { returnTo: props.returnTo() } }),
        )
        return
      }
      if (kind === 'import') {
        const job = await startTraktImport()
        await navigate({ to: '/app/imports/$id', params: { id: job.id } })
        return
      }
      await disconnectTrakt()
      props.onDisconnected()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'Trakt could not be reached.',
      )
    }
    setBusy(undefined)
  }

  return (
    <div class="flex flex-col gap-2 rounded-card border border-line p-4 sm:col-span-2">
      <span class="font-medium">Import from Trakt</span>
      <Show
        when={props.connection.connected}
        fallback={
          <>
            <span class="max-w-[60ch] text-xs text-muted">
              Sign in on trakt.tv and Aaru reads your watched history, episodes,
              watchlist, ratings and lists. Free Trakt accounts can connect two
              apps.
            </span>
            <Button
              class="self-start"
              disabled={busy() !== undefined}
              onClick={() => void run('connect')}
            >
              {busy() === 'connect' ? 'Opening Trakt…' : 'Connect Trakt'}
            </Button>
          </>
        }
      >
        <span class="text-xs text-muted">
          Connected
          {props.connection.username ? ` as ${props.connection.username}` : ''}.
          Import again any time: it only fills gaps and never undoes what you
          set in Aaru.
        </span>
        <div class="flex flex-wrap items-center gap-3">
          <Button
            disabled={busy() !== undefined}
            onClick={() => void run('import')}
          >
            {busy() === 'import' ? 'Starting…' : 'Import from Trakt'}
          </Button>
          <button
            type="button"
            class="text-sm font-semibold text-accent hover:underline disabled:opacity-50"
            disabled={busy() !== undefined}
            onClick={() => void run('disconnect')}
          >
            {busy() === 'disconnect' ? 'Disconnecting…' : 'Disconnect'}
          </button>
        </div>
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
      <span class="text-xs text-muted">{TRAKT_NOTICE}</span>
    </div>
  )
}
