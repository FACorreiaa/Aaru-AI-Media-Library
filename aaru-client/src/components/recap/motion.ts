import { createSignal, onCleanup, onMount } from 'solid-js'
import { prefersReducedMotion } from '../../lib/motion'

/** A number that counts up from zero once, easing out; the final value at once with reduced motion. */
export function createCountUp(target: () => number, ms = 1200) {
  const [value, setValue] = createSignal(0)
  onMount(() => {
    if (prefersReducedMotion()) {
      setValue(target())
      return
    }
    const start = performance.now()
    let frame = 0
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / ms)
      setValue(Math.round(target() * (1 - Math.pow(1 - t, 3))))
      if (t < 1) frame = requestAnimationFrame(step)
    }
    frame = requestAnimationFrame(step)
    onCleanup(() => cancelAnimationFrame(frame))
  })
  return value
}
