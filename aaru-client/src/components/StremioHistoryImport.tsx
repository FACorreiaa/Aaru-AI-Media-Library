import { useNavigate } from '@tanstack/solid-router'
import { Show, createSignal, onCleanup } from 'solid-js'
import { pollStremioImport, startStremioImport } from '../lib/imports/server'
import type { StremioLink } from '../lib/imports/server'
import { cn } from '~/lib/utils'
import { Button, buttonVariants } from '~/components/ui'

const POLL_MS = 3000

// IMP-016: bring in what was watched in Stremio before the addon was installed. The user
// approves a code on stremio.com; Aaru reads the library once, logs out, and plans an import
// that waits for approval like any other.
export function StremioHistoryImport(props: { class?: string }) {
  const navigate = useNavigate()
  const [link, setLink] = createSignal<StremioLink | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  let timer: ReturnType<typeof setTimeout> | undefined

  const stop = () => {
    if (timer !== undefined) clearTimeout(timer)
    timer = undefined
  }
  onCleanup(stop)

  const fail = (error: unknown, fallback: string) => {
    stop()
    setLink(null)
    setProblem(error instanceof Error ? error.message : fallback)
  }

  async function poll(code: string) {
    try {
      const answer = await pollStremioImport({ data: { code } })
      if (answer.state === 'imported') {
        stop()
        await navigate({
          to: '/app/imports/$id',
          params: { id: answer.job.id },
        })
        return
      }
      timer = setTimeout(() => void poll(code), POLL_MS)
    } catch (error) {
      fail(error, 'Your Stremio history could not be imported.')
    }
  }

  async function start() {
    setBusy(true)
    setProblem(null)
    try {
      const fresh = await startStremioImport()
      setLink(fresh)
      timer = setTimeout(() => void poll(fresh.code), POLL_MS)
    } catch (error) {
      fail(error, 'Stremio could not be reached. Try again in a minute.')
    } finally {
      setBusy(false)
    }
  }

  function cancel() {
    stop()
    setLink(null)
  }

  return (
    <div class={props.class}>
      <Show
        when={link()}
        fallback={
          <div class="flex flex-col gap-2">
            <p class="max-w-[60ch] text-sm text-muted">
              Already watched things in Stremio? Bring your library, watched
              films and ticked episodes in once. You approve it on stremio.com;
              your Stremio password never reaches Aaru.
            </p>
            <Button
              variant="outline"
              class="self-start"
              disabled={busy()}
              onClick={() => void start()}
            >
              {busy() ? 'Starting…' : 'Import my Stremio history'}
            </Button>
          </div>
        }
      >
        {(current) => (
          <div class="flex flex-wrap items-start gap-5 rounded-panel border border-line p-4">
            <img
              src={current().qrcode}
              alt="QR code that opens the Stremio approval page"
              width="132"
              height="132"
              class="rounded-lg bg-white p-1"
            />
            <div class="flex min-w-0 flex-1 flex-col gap-3">
              <p class="text-sm">
                Sign in to Stremio and approve code{' '}
                <span class="font-mono text-base font-semibold tracking-widest">
                  {current().code}
                </span>
                . Scan the code with your phone, or open the page here.
              </p>
              <a
                href={current().link}
                target="_blank"
                rel="noopener noreferrer"
                class={cn(buttonVariants({ variant: 'default' }), 'self-start')}
              >
                Approve on stremio.com
              </a>
              <p class="text-xs text-muted" aria-live="polite">
                Waiting for approval. This page moves on by itself.
              </p>
              <button
                type="button"
                class="self-start text-sm font-semibold text-accent hover:underline"
                onClick={cancel}
              >
                Cancel
              </button>
            </div>
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
    </div>
  )
}
