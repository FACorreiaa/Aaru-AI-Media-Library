/** The streaming sites the extension reads, as the server names them. */
export type Source = 'netflix' | 'disney_plus' | 'prime_video'

export const SOURCE_LABELS: Record<Source, string> = {
  netflix: 'Netflix',
  disney_plus: 'Disney+',
  prime_video: 'Prime Video',
}

/** What a player page says is playing. No ids: these sites have none Aaru knows. */
export interface Playing {
  source: Source
  /** The site's own id for one film or one episode. */
  ref: string
  type: 'movie' | 'show'
  title: string
  year?: number
  season?: number
  episode?: number
  episodeTitle?: string
}

/** One look at the page: what plays, where the main video is, and whether it is running. */
export interface Observation {
  playing: Playing | null
  positionMs: number
  durationMs: number
  paused: boolean
  ended: boolean
}

export type Action = 'start' | 'pause' | 'stop'

/** One scrobble to send. `progress` is a percentage. */
export interface Call {
  action: Action
  playing: Playing
  progress: number
  durationMs: number
}

/** "Severance · S2 · E3" or "Roma". */
export function label(playing: Playing): string {
  if (playing.type === 'movie') return playing.title
  const parts = [playing.title]
  if (playing.season !== undefined) parts.push(`S${playing.season}`)
  if (playing.episode !== undefined) parts.push(`E${playing.episode}`)
  return parts.join(' · ')
}
