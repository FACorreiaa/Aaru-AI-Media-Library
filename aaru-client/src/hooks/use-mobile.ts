// https://github.com/solidjs-community/solid-primitives/blob/main/packages/media/src/index.ts

import { createSignal, onCleanup, onMount } from 'solid-js'

/**
 * True while the viewport is at most `maxWidth` px wide (shadcn's 767 by default).
 *
 * Aaru: the width is a parameter so the sidebar can switch at its own 1024px (DESIGN.md §18)
 * without moving every other caller, and the first value is `false` on the client as on the
 * server, read on mount, so hydration renders the same tree the server sent.
 */
export const useIsMobile = (maxWidth = 767) => {
  const [state, setState] = createSignal(false)
  onMount(() => {
    const mql = window.matchMedia(`(max-width: ${maxWidth}px)`)
    const update = () => setState(mql.matches)
    update()
    mql.addEventListener('change', update)
    onCleanup(() => mql.removeEventListener('change', update))
  })
  return state
}
