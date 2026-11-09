// Its own module: route options are not code-split, so what the welcome route's `beforeLoad`
// imports ships in the entry chunk every page loads (see `search-params.ts`).

/** Where the first run sends you when it ends, never back into itself. */
export function welcomeNext(next: string): string {
  return next === '/app/welcome' || next.startsWith('/app/welcome?')
    ? '/app'
    : next
}
