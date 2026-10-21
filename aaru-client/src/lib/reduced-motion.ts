// Its own module, apart from `motion.ts`: a page that only asks this question (Recap's
// count-up, a row's scroll) must not download the animation library with the answer.

/** The viewer asked for less motion. False on the server: the page renders still, then moves. */
export function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  )
}
