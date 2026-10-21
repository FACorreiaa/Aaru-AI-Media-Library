import type { Playing } from '../lib/types'
import { deepQuery, seasonEpisode, text } from './dom'

// Disney+'s player at `/play/{id}` (also `/video/{id}`): the id is one film or one episode. The
// overlay's `.title-field` is the film or show, `.subtitle-field` is `S2:E3 Episode title` for an
// episode. Newer players keep both inside the player element's shadow root.
export function readDisneyPlus(doc: Document, url: URL): Playing | null {
  const id = /^\/(?:[a-z]{2}-[a-z]{2}\/)?(?:play|video)\/([\w-]+)/i.exec(
    url.pathname,
  )?.[1]
  if (!id) return null
  const title = text(deepQuery(doc, '.title-field'))
  if (!title) return null
  const subtitle = text(deepQuery(doc, '.subtitle-field'))
  const numbered = subtitle ? seasonEpisode(subtitle) : null
  if (!numbered) return { source: 'disney_plus', ref: id, type: 'movie', title }
  return {
    source: 'disney_plus',
    ref: id,
    type: 'show',
    title,
    season: numbered.season,
    episode: numbered.episode,
    episodeTitle: numbered.rest || undefined,
  }
}
