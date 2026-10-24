// The "Credit Aaru shows" column of docs/providers.md (PRV-001). Change both together.

/** TMDB's required notice, word for word. */
export const TMDB_NOTICE =
  'This product uses the TMDB API but is not endorsed or certified by TMDB.'

export const TMDB_URL = 'https://www.themoviedb.org'

/** Trakt's API use policy asks for this line wherever the integration is offered. */
export const TRAKT_NOTICE =
  'Aaru uses Trakt but is not endorsed or certified by Trakt.'

export const CONTACT_EMAIL = 'privacy@aaruapp.com'

export interface Credit {
  /** Text before the linked name, e.g. "Air times from ". */
  lead: string
  name: string
  href: string
  licence?: { name: string; href: string }
}

export const CREDITS: Credit[] = [
  {
    lead: 'Air times from ',
    name: 'TVmaze',
    href: 'https://www.tvmaze.com',
    licence: {
      name: 'CC BY-SA 4.0',
      href: 'https://creativecommons.org/licenses/by-sa/4.0/',
    },
  },
  {
    lead: 'Where to stream from ',
    name: 'JustWatch',
    href: 'https://www.justwatch.com',
  },
  { lead: 'Anime data from ', name: 'AniList', href: 'https://anilist.co' },
  {
    lead: 'Anime id mappings from ',
    name: 'Fribb/anime-lists',
    href: 'https://github.com/Fribb/anime-lists',
    licence: { name: 'MIT', href: 'https://opensource.org/license/mit' },
  },
  {
    lead: 'Book data from ',
    name: 'Open Library',
    href: 'https://openlibrary.org',
  },
  {
    lead: 'Music data from ',
    name: 'MusicBrainz',
    href: 'https://musicbrainz.org',
    licence: {
      name: 'CC0',
      href: 'https://creativecommons.org/publicdomain/zero/1.0/',
    },
  },
  {
    lead: 'Album rows from ',
    name: 'ListenBrainz',
    href: 'https://listenbrainz.org',
  },
  {
    lead: 'Album covers from ',
    name: 'Cover Art Archive',
    href: 'https://coverartarchive.org',
  },
  {
    lead: 'Concerts from ',
    name: 'Ticketmaster',
    href: 'https://www.ticketmaster.com',
  },
  {
    lead: 'Sports data from ',
    name: 'TheSportsDB',
    href: 'https://www.thesportsdb.com',
  },
  {
    lead: 'City search by ',
    name: 'Open-Meteo',
    href: 'https://open-meteo.com',
  },
  { lead: 'History import from ', name: 'Trakt', href: 'https://trakt.tv' },
]
