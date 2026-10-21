import { onCleanup, onMount } from 'solid-js'

/**
 * Runs `tick` every `ms` while the page is visible and `enabled` holds, and once when the page
 * becomes visible again. With the realtime socket (GRP-006) this is only the fallback for while
 * the socket is down.
 */
export function useVisiblePoll(
  tick: () => Promise<void> | void,
  ms: number,
  enabled: () => boolean = () => true,
) {
  onMount(() => {
    let running = false
    const run = async () => {
      if (running || document.visibilityState !== 'visible' || !enabled())
        return
      running = true
      try {
        await tick()
      } catch {
        // A missed poll is retried on the next tick.
      } finally {
        running = false
      }
    }
    const timer = window.setInterval(() => void run(), ms)
    const onVisible = () => {
      if (document.visibilityState === 'visible') void run()
    }
    document.addEventListener('visibilitychange', onVisible)
    onCleanup(() => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
    })
  })
}
