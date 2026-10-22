import { browser, defineContentScript } from '#imports'
import type { Browser } from '#imports'
import { PLAYER_PORT } from '../lib/protocol'
import { contentReporter } from '../lib/reporting/content'
import type { Observation, Playing } from '../lib/types'
import { mainVideo } from '../sites/dom'
import { SITE_MATCHES, readerFor, remembers } from '../sites/index'

/** A playing page reports at least this often; the background decides what to send. */
const REPORT_MS = 15_000
/** How often the page is looked at between video events. */
const LOOK_MS = 2_000

// SCR-007: reads what plays from the player's own title overlay and URL, follows the main video,
// and reports to the background. It draws nothing on the page and never touches the player.
export default defineContentScript({
  matches: SITE_MATCHES,
  runAt: 'document_idle',
  main(ctx) {
    // An error here goes to the background, which reports it with the site's origin only
    // (the path names what plays). Nothing is installed on the page: what can fail runs
    // inside `reporter.guard`.
    const reporter = contentReporter()
    const read = readerFor(location.hostname)
    if (!read) return
    // The overlay hides between mouse moves: what was read stays known for that page.
    const known = new Map<string, Playing>()
    const remember = remembers(read)
    let port: Browser.runtime.Port | null = null
    let last = ''
    let lastAt = 0

    const look = (): Observation => {
      const fresh = read(document, new URL(location.href))
      const key = location.pathname + location.search
      if (fresh && remember) known.set(key, fresh)
      const video = mainVideo(document)
      return {
        playing: fresh ?? known.get(key) ?? null,
        positionMs: video ? Math.round(video.currentTime * 1000) : 0,
        durationMs:
          video && Number.isFinite(video.duration)
            ? Math.round(video.duration * 1000)
            : 0,
        paused: video ? video.paused : true,
        ended: video ? video.ended : false,
      }
    }

    const report = reporter.guard((force: boolean = false) => {
      const seen = look()
      const signature = JSON.stringify([
        seen.playing?.ref,
        seen.paused,
        seen.ended,
      ])
      if (!force && signature === last && Date.now() - lastAt < REPORT_MS)
        return
      last = signature
      lastAt = Date.now()
      if (!seen.playing && !port) return
      try {
        port ??= connect()
        port.postMessage(seen)
      } catch {
        port = null
      }
    })

    const connect = () => {
      const opened = browser.runtime.connect({ name: PLAYER_PORT })
      opened.onDisconnect.addListener(() => {
        if (port === opened) port = null
      })
      return opened
    }

    for (const type of ['play', 'pause', 'ended', 'seeked'])
      document.addEventListener(type, () => report(true), true)
    ctx.setInterval(() => report(), LOOK_MS)
    ctx.onInvalidated(() => port?.disconnect())
  },
})
