// "Add to my Aaru" on a share link, signed out: this browser remembers which link asked, so the
// page saves the title on the way back from sign-in. `?add=1` alone never saves anything, or a
// link carrying it would write to the library of any signed-in person who opened it. Local
// storage, not session storage: the emailed sign-in link opens in a new tab.
const KEY = 'aaru.share-add'
const LIFETIME_MS = 15 * 60 * 1000

export function rememberAdd(code: string, now = Date.now()) {
  try {
    localStorage.setItem(KEY, JSON.stringify({ code, at: now }))
  } catch {
    // Storage blocked: back from sign-in, the page offers Add instead.
  }
}

/** Whether this browser asked to save this link's title, lately; asks once. */
export function takeAdd(code: string, now = Date.now()): boolean {
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return false
    const saved = JSON.parse(raw) as { code?: unknown; at?: unknown }
    if (saved.code !== code) return false
    localStorage.removeItem(KEY)
    return typeof saved.at === 'number' && now - saved.at <= LIFETIME_MS
  } catch {
    return false
  }
}
