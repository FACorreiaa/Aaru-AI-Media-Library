/** The sites the extension reads, as the server names them. */
export type Source = 'netflix' | 'disney_plus' | 'prime_video' | 'youtube'

export const SOURCE_LABELS: Record<Source, string> = {
  netflix: 'Netflix',
  disney_plus: 'Disney+',
  prime_video: 'Prime Video',
  youtube: 'YouTube',
}

/** What a player page says is playing: a film or an episode, or a YouTube video. */
export type Playing = FilmOrEpisode | Video

/** A film or an episode on a streaming site. No ids: these sites have none Aaru knows. */
export interface FilmOrEpisode {
  source: Exclude<Source, 'youtube'>
  /** The site's own id for one film or one episode. */
  ref: string
  type: 'movie' | 'show'
  title: string
  year?: number
  season?: number
  episode?: number
  episodeTitle?: string
}

/** SCR-009: a YouTube video. Aaru shows it as playing and never matches it to a title. */
export interface Video {
  source: 'youtube'
  /** The video's id, the `v` of `/watch?v=…`. */
  ref: string
  type: 'video'
  title: string
  channel?: string
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

/** "Severance · S2 · E3", "Roma", or "Video title · Channel". */
export function label(playing: Playing): string {
  if (playing.type === 'movie') return playing.title
  if (playing.type === 'video')
    return [playing.title, playing.channel].filter(Boolean).join(' · ')
  const parts = [playing.title]
  if (playing.season !== undefined) parts.push(`S${playing.season}`)
  if (playing.episode !== undefined) parts.push(`E${playing.episode}`)
  return parts.join(' · ')
}
