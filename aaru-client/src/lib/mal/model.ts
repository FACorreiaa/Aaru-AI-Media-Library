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
          'MyAnimeList is connected. From now on the two lists keep each other up to date.',
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

/** "Last read 5 min ago": when Aaru last read the MyAnimeList list back; null before any read. */
export function malLastRead(
  connection: MALConnection,
  now = new Date(),
): string | null {
  if (!connection.pulledAt) return null
  const minutes = Math.floor(
    (now.getTime() - new Date(connection.pulledAt).getTime()) / 60_000,
  )
  if (minutes < 1) return 'Last read just now'
  if (minutes < 60) return `Last read ${minutes} min ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `Last read ${hours} h ago`
  const days = Math.floor(hours / 24)
  return days === 1 ? 'Last read yesterday' : `Last read ${days} days ago`
}
