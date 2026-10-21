import type { Playing } from '../lib/types'
import { deepQuery, seasonEpisode, text } from './dom'

// Netflix's player at `/watch/{id}`: the id is one film or one episode. While the controls show,
// `[data-uia="video-title"]` holds the title — for an episode an `<h4>` with the show, then
// spans with `S2:E3` and the episode's title. Read once per id; the overlay hides again.
export function readNetflix(doc: Document, url: URL): Playing | null {
  const id = /^\/watch\/(\d+)/.exec(url.pathname)?.[1]
  if (!id) return null
  const overlay = deepQuery(doc, '[data-uia="video-title"]')
  if (!overlay) return null
  const show = text(overlay.querySelector('h4'))
  const spans = [...overlay.querySelectorAll('span')].map(text).filter(Boolean)
  if (show && spans.length > 0) {
    const numbered = seasonEpisode(spans.join(' '))
    const limited =
      /^(?:Limited Series|Miniseries|Collection)?\s*:?\s*E(\d{1,4})$/i.exec(
        spans[0] ?? '',
      )
    return {
      source: 'netflix',
      ref: id,
      type: 'show',
      title: show,
      season: numbered?.season ?? (limited ? 1 : undefined),
      episode: numbered?.episode ?? (limited ? Number(limited[1]) : undefined),
      episodeTitle: (numbered ? numbered.rest : spans.at(-1)) || spans.at(-1),
    }
  }
  const title = text(overlay)
  return title ? { source: 'netflix', ref: id, type: 'movie', title } : null
}
