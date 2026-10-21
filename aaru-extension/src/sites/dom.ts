/** The first element matching `selector` in the page or any open shadow root under it. */
export function deepQuery(root: ParentNode, selector: string): Element | null {
  const found = root.querySelector(selector)
  if (found) return found
  for (const element of root.querySelectorAll('*')) {
    if (element.shadowRoot) {
      const inner = deepQuery(element.shadowRoot, selector)
      if (inner) return inner
    }
  }
  return null
}

export const text = (element: Element | null | undefined): string =>
  element?.textContent.replace(/\s+/g, ' ').trim() ?? ''

/** `S2:E3`, `S2 E3`, `Season 2, Ep. 3`, `Season 2 Episode 3`, at the start of a subtitle; the
 * rest is the episode's title. */
export function seasonEpisode(
  subtitle: string,
): { season: number; episode: number; rest: string } | null {
  const match =
    /^(?:S|Season\s*)(\d{1,3})\s*[:,]?\s*(?:E|Ep\.?|Episode)\s*(\d{1,4})\s*[:.\-–—]?\s*(.*)$/i.exec(
      subtitle.trim(),
    )
  if (!match) return null
  return {
    season: Number(match[1]),
    episode: Number(match[2]),
    rest: (match[3] ?? '').trim(),
  }
}

/** The page's main video: the longest one that has loaded. Ads and previews are shorter. */
export function mainVideo(root: ParentNode): HTMLVideoElement | null {
  let best: HTMLVideoElement | null = null
  for (const video of root.querySelectorAll('video')) {
    if (!Number.isFinite(video.duration) || video.duration <= 0) continue
    if (!best || video.duration > best.duration) best = video
  }
  return best
}
