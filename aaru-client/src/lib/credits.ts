// The "Credit Aaru shows" column of docs/providers.md (PRV-001). Change both together.

/** TMDB's required notice, word for word. */
export const TMDB_NOTICE =
  'This product uses the TMDB API but is not endorsed or certified by TMDB.'

export const TMDB_URL = 'https://www.themoviedb.org'

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
  { lead: 'Anime data from ', name: 'AniList', href: 'https://anilist.co' },
  {
    lead: 'Book data from ',
    name: 'Open Library',
    href: 'https://openlibrary.org',
  },
]
