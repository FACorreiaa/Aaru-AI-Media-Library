import type { Playing } from '../lib/types'
import { deepQuery, seasonEpisode, text } from './dom'

// Prime Video's player opens over a title's page (`/detail/{asin}`, or `/gp/video/detail/{asin}`
// on Amazon). `.atvwebplayersdk-title-text` is the film or show; for an episode
// `.atvwebplayersdk-subtitle-text` reads `Season 2, Ep. 3 Episode title`. The page's id is the
// title's, so an episode's ref adds its numbers.
export function readPrimeVideo(doc: Document, url: URL): Playing | null {
  const title = text(deepQuery(doc, '.atvwebplayersdk-title-text'))
  if (!title) return null
  const asin =
    /\/(?:gp\/video\/)?detail\/([\w.-]+)/.exec(url.pathname)?.[1] ??
    url.searchParams.get('gti') ??
    title
  const subtitle = text(deepQuery(doc, '.atvwebplayersdk-subtitle-text'))
  const numbered = subtitle ? seasonEpisode(subtitle) : null
  if (!numbered)
    return { source: 'prime_video', ref: asin, type: 'movie', title }
  return {
    source: 'prime_video',
    ref: `${asin}:${numbered.season}:${numbered.episode}`,
    type: 'show',
    title,
    season: numbered.season,
    episode: numbered.episode,
    episodeTitle: numbered.rest || undefined,
  }
}
