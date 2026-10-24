import type { MALConnection } from './server'

/** What MyAnimeList's redirect back (`?mal=`) means, in words; null for anything else. */
export function malResult(
  value: string | undefined,
): { ok: boolean; message: string } | null {
  switch (value) {
    case 'connected':
      return {
        ok: true,
        message:
          'MyAnimeList is connected. Anime you update from now on go to your list.',
      }
    case 'denied':
      return {
        ok: false,
        message: 'MyAnimeList was not connected: access was declined.',
      }
    case 'failed':
      return {
        ok: false,
        message: 'MyAnimeList could not finish connecting. Try again.',
      }
    default:
      return null
  }
}

/** "Connected as ana · since 23 Oct"; the name or the date is left out when unknown. */
export function malConnectedLabel(connection: MALConnection): string {
  const who = connection.username
    ? `Connected as ${connection.username}`
    : 'Connected'
  if (!connection.connectedAt) return who
  const since = new Date(connection.connectedAt).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
  })
  return `${who} · since ${since}`
}
