import type { Playing } from '../lib/types'
import { text } from './dom'

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/

// SCR-009: YouTube's watch page, `www.youtube.com/watch?v={id}`, only. Not Shorts, not
// music.youtube.com (Web Scrobbler already sends that through ListenBrainz), not a live stream,
// and nothing while an ad plays in the player. The title is `ytd-watch-metadata h1`, the channel
// its `ytd-channel-name` link. YouTube moves between videos without a reload: the page's
// `ytd-watch-flexy[video-id]` must name the URL's video, or the title may still be the last one's.
export function readYouTube(doc: Document, url: URL): Playing | null {
  if (url.hostname !== 'www.youtube.com' || url.pathname !== '/watch')
    return null
  const id = url.searchParams.get('v') ?? ''
  if (!VIDEO_ID.test(id)) return null
  const shown = doc.querySelector('ytd-watch-flexy')?.getAttribute('video-id')
  if (shown && shown !== id) return null
  const player = doc.querySelector('#movie_player')
  if (player?.matches('.ad-showing, .ad-interrupting, .ytp-live')) return null
  const video = doc.querySelector<HTMLVideoElement>(
    '#movie_player video, video.html5-main-video',
  )
  if (video && !Number.isFinite(video.duration)) return null
  const title =
    text(doc.querySelector('ytd-watch-metadata h1')) ||
    text(doc.querySelector('#movie_player .ytp-title-link'))
  if (!title) return null
  const channel =
    text(doc.querySelector('ytd-watch-metadata ytd-channel-name a')) ||
    text(doc.querySelector('ytd-video-owner-renderer ytd-channel-name a'))
  return {
    source: 'youtube',
    ref: id,
    type: 'video',
    title,
    channel: channel || undefined,
  }
}
