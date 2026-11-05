import type { ChatHint } from './thread'

// Where the user is, for the assistant's prompt: a screen the server knows, and on a title page
// the title. A path the server has no name for is sent as nothing.

const SCREENS: Array<[string, string]> = [
  ['/app/discover', 'discover'],
  ['/app/library', 'library'],
  ['/app/calendar', 'calendar'],
  ['/app/week', 'calendar'],
  ['/app/lists', 'lists'],
  ['/app/friends', 'friends'],
  ['/app/groups', 'groups'],
  ['/app/books', 'books'],
  ['/app/manga', 'manga'],
  ['/app/music', 'music'],
  ['/app/sports', 'sports'],
  ['/app/insights', 'insights'],
  ['/app/title', 'title'],
]

export function screenOf(pathname: string): string | null {
  const path = pathname.replace(/\/+$/, '') || '/'
  if (path === '/app') return 'home'
  for (const [prefix, screen] of SCREENS) {
    if (path === prefix || path.startsWith(prefix + '/')) return screen
  }
  return null
}

export function hintFor(
  pathname: string,
  titleId: string | null,
): ChatHint | undefined {
  const screen = screenOf(pathname)
  if (!screen) return undefined
  return screen === 'title' && titleId ? { screen, titleId } : { screen }
}
