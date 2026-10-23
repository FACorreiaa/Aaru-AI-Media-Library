import type { components } from '../api/schema'

type RankedTonight = components['schemas']['Tonight']

// The last server answer, so Tonight opens offline and before the request lands. Per browser,
// cleared on sign-out; storage may be blocked, so every read and write is guarded.
const CACHE_KEY = 'aaru.tonight'

export function rememberTonight(ranked: RankedTonight) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(ranked))
  } catch {
    // Storage blocked: Tonight waits for the server next time.
  }
}

/** The last answer, if it is for `day`; null otherwise. */
export function recalledTonight(day: string): RankedTonight | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY)
    if (!raw) return null
    const saved = JSON.parse(raw) as Partial<RankedTonight>
    return saved.day === day && Array.isArray(saved.picks)
      ? (saved as RankedTonight)
      : null
  } catch {
    return null
  }
}

export function forgetTonight() {
  try {
    localStorage.removeItem(CACHE_KEY)
  } catch {
    // Nothing stored, or storage blocked.
  }
}
