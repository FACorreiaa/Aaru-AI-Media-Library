import type { components } from '../api/schema'

// MUS-001: an album's Title room shows its tracklist. Read only: no playback, no ticks.

export type AlbumTrack = components['schemas']['AlbumTrack']

export interface Disc {
  number: number
  tracks: AlbumTrack[]
}

/** "3:07", "12:45", "1:02:09": a track's length on a clock. Empty when it is unknown. */
export function trackLength(ms?: number | null): string {
  if (ms == null || !Number.isFinite(ms) || ms <= 0) return ''
  const total = Math.round(ms / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = String(total % 60).padStart(2, '0')
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`
}

/** Tracks by disc, discs and positions ascending. One disc when the album has one. */
export function discs(tracks: AlbumTrack[]): Disc[] {
  const byDisc = new Map<number, AlbumTrack[]>()
  for (const track of tracks) {
    const list = byDisc.get(track.disc) ?? []
    list.push(track)
    byDisc.set(track.disc, list)
  }
  return [...byDisc.entries()]
    .sort(([a], [b]) => a - b)
    .map(([number, list]) => ({
      number,
      tracks: [...list].sort((a, b) => a.position - b.position),
    }))
}

/** "12 tracks · 53 min" under the tracklist. The time only when every track has a length,
 * so a partly known album never reads shorter than it is. */
export function albumSummary(tracks: AlbumTrack[]): string {
  const count = `${tracks.length} track${tracks.length === 1 ? '' : 's'}`
  const known = tracks.every((t) => t.lengthMs != null && t.lengthMs > 0)
  if (!known || tracks.length === 0) return count
  const minutes = Math.round(
    tracks.reduce((sum, t) => sum + (t.lengthMs ?? 0), 0) / 60_000,
  )
  if (minutes < 60) return `${count} · ${minutes} min`
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return `${count} · ${m === 0 ? `${h} h` : `${h} h ${m} min`}`
}

/** The Cover Art Archive URL at 500 px, for the Title room's big cover: catalog rows get the
 * 250 px thumbnail, which blurs at that size. Any other URL is left alone. */
export function largeCover(url?: string): string | undefined {
  return url?.replace(/\/front-250$/, '/front-500')
}
