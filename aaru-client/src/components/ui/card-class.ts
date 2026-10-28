/** Aaru: the plain surface panel, for an element that is not a `Card` (a `<details>`, a link,
 *  a grid cell). No imports, on purpose: see card.tsx. */
export const cardClass = 'rounded-card border border-line bg-surface'

/** Aaru: the one chip for a link that filters or opens (Home's status counts and lists), the same
 *  look as `Segmented`'s `chip`. Taller where the pointer is a finger. */
export const chipClass =
  'inline-flex min-h-9 items-center gap-1.5 rounded-full border border-line px-4 text-sm font-medium hover:bg-surface pointer-coarse:min-h-11'
