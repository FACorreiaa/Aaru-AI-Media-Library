import { onCleanup, onMount } from 'solid-js'
import { PENDING_RETRY_MS, refreshDelay } from './model'
import type { LiveState } from './model'

/**
 * SPT-003's near-live loop for one Sports view. After each answer the view calls `plan` with
 * what it shows: a live event asks again in 90 s, a `pending` answer in 4 s (a few times in a
 * row at most), anything else not at all. Nothing runs while the page is hidden; coming back
 * to a view that was live or pending asks at once. `refresh` asks quietly (no spinner over what
 * is there) and answers the new state, or null when a newer load took over.
 */
export function createNearLive(refresh: () => Promise<LiveState | null>) {
  let timer: ReturnType<typeof setTimeout> | undefined
  let tries = 0
  let last: LiveState | null = null
  const visible = () => document.visibilityState === 'visible'

  function stop() {
    clearTimeout(timer)
    timer = undefined
  }

  function plan(state: LiveState | null) {
    stop()
    if (!state) return
    last = state
    if (!state.pending) tries = 0
    if (!visible()) return
    const delay = refreshDelay(state, tries)
    if (delay === null) return
    if (state.pending && delay === PENDING_RETRY_MS) tries++
    timer = setTimeout(() => void run(), delay)
  }

  async function run() {
    timer = undefined
    if (!visible()) return
    plan(await refresh())
  }

  /** What is shown changed on a tap (another day): pending retries start again. */
  function reset() {
    tries = 0
  }

  onMount(() => {
    const changed = () => {
      if (!visible()) return stop()
      if (last && (last.live || last.pending) && timer === undefined) {
        tries = 0
        void run()
      }
    }
    document.addEventListener('visibilitychange', changed)
    onCleanup(() => {
      stop()
      document.removeEventListener('visibilitychange', changed)
    })
  })

  return { plan, reset }
}
