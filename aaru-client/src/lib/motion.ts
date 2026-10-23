import type { animate } from 'motion/mini'
import { prefersReducedMotion } from './reduced-motion'
import { MOTION } from './tokens.gen'

// The web's motion helpers (DESIGN.md §17). CSS keyframes stay the default; these are for what
// CSS cannot do: an exit before an element leaves the DOM, siblings sliding into a gap (FLIP),
// and direction-aware swaps. Only transform and opacity move, through `motion/mini` (native
// WAAPI, about 3 KB). With reduced motion nothing animates and every promise resolves at once.
// Every animation follows a tap, so `motion/mini` stays off the routes' critical path: it loads
// on its own when the browser is idle after a page that uses it, or on the first animation.

/** The same ease-out as the CSS `.rise` entrance. */
export const EASE_OUT = MOTION.easeBezier

const DURATION = MOTION.base / 1000

type Frames = Parameters<typeof animate>[1]

let engine: Promise<typeof animate> | undefined
function load(): Promise<typeof animate> {
  engine ??= import('motion/mini').then((m) => m.animate)
  return engine
}

if (typeof window !== 'undefined' && !prefersReducedMotion()) {
  const warm = () => void load()
  if ('requestIdleCallback' in window) requestIdleCallback(warm)
  else setTimeout(warm, 1)
}

/** No animation on the server, nor for a viewer who asked for less motion. */
function still(): boolean {
  return typeof window === 'undefined' || prefersReducedMotion()
}

/** Plays `frames` on `el` once; resolves when done, or at once with reduced motion. */
export async function play(
  el: Element,
  frames: Frames,
  duration = DURATION,
): Promise<void> {
  if (still()) return
  const animate = await load()
  await animate(el, frames, { duration, ease: [...EASE_OUT] })
}

/** An element leaving: fade and shrink a little. Remove it from state after this resolves. */
export function leave(el: Element): Promise<void> {
  return play(el, { opacity: [1, 0], transform: ['scale(1)', 'scale(0.96)'] })
}

/** A user's tick landing: one short scale up to rest, no overshoot. Never on load. */
export function pop(el: Element): Promise<void> {
  return play(el, { transform: ['scale(0.85)', 'scale(1)'] }, 0.2)
}

/** A view arriving from one side: `direction` 1 comes from the right, -1 from the left. */
export function slideIn(el: Element, direction: 1 | -1): Promise<void> {
  return play(el, {
    opacity: [0, 1],
    transform: [`translateX(${direction * 16}px)`, 'translateX(0)'],
  })
}

/**
 * FLIP: records where `container`'s children are, runs `mutate` (a state change Solid applies
 * synchronously), then slides every child that moved from its old place to its new one.
 */
export async function flip(
  container: Element,
  mutate: () => void,
): Promise<void> {
  if (still()) {
    mutate()
    return
  }
  // Loaded before measuring, so the moved children never paint a frame in their new place first.
  await load()
  const before = new Map<Element, DOMRect>()
  for (const child of container.children) {
    before.set(child, child.getBoundingClientRect())
  }
  mutate()
  const moves: Promise<void>[] = []
  for (const child of container.children) {
    const old = before.get(child)
    if (!old) continue
    const now = child.getBoundingClientRect()
    const dx = old.left - now.left
    const dy = old.top - now.top
    if (dx === 0 && dy === 0) continue
    moves.push(
      play(child, {
        transform: [`translate(${dx}px, ${dy}px)`, 'translate(0, 0)'],
      }),
    )
  }
  await Promise.all(moves)
}
