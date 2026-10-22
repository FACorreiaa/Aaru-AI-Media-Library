import type { Playing } from '../lib/types'
import { readDisneyPlus } from './disneyplus'
import { readNetflix } from './netflix'
import { readPrimeVideo } from './primevideo'
import { readYouTube } from './youtube'

export type Reader = (doc: Document, url: URL) => Playing | null

/** The reader for the site a page is on; null elsewhere. */
export function readerFor(host: string): Reader | null {
  if (host === 'www.netflix.com') return readNetflix
  if (host === 'www.disneyplus.com') return readDisneyPlus
  if (host === 'www.primevideo.com' || /^www\.amazon\.[a-z.]+$/.test(host))
    return readPrimeVideo
  if (host === 'www.youtube.com') return readYouTube
  return null
}

/** Whether what a reader saw on a page stands in while it sees nothing. Yes where the title
 * overlay hides between mouse moves; not on YouTube, whose title stays on the page, so seeing
 * nothing there means nothing plays (an ad, or the next video still loading). */
export const remembers = (read: Reader): boolean => read !== readYouTube

/** Where the content script runs. Amazon only under its video pages; all of YouTube, which moves
 * to a watch page without a reload. */
export const SITE_MATCHES = [
  'https://www.netflix.com/*',
  'https://www.disneyplus.com/*',
  'https://www.primevideo.com/*',
  ...[
    'com',
    'co.uk',
    'de',
    'fr',
    'it',
    'es',
    'ca',
    'com.br',
    'com.mx',
    'com.au',
    'co.jp',
    'in',
    'nl',
  ].map((tld) => `https://www.amazon.${tld}/gp/video/*`),
  'https://www.youtube.com/*',
]
