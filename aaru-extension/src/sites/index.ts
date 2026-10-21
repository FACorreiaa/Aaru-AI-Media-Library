import type { Playing } from '../lib/types'
import { readDisneyPlus } from './disneyplus'
import { readNetflix } from './netflix'
import { readPrimeVideo } from './primevideo'

export type Reader = (doc: Document, url: URL) => Playing | null

/** The reader for the site a page is on; null elsewhere. */
export function readerFor(host: string): Reader | null {
  if (host === 'www.netflix.com') return readNetflix
  if (host === 'www.disneyplus.com') return readDisneyPlus
  if (host === 'www.primevideo.com' || /^www\.amazon\.[a-z.]+$/.test(host))
    return readPrimeVideo
  return null
}

/** Where the content script runs. Amazon only under its video pages. */
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
]
