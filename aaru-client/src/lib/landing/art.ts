// LAND-001: the landing page's artwork. Hotlinked from each catalog's own image host, never
// downloaded or hosted (CLAUDE.md). Every URL here was checked by hand to return its cover.

const tmdb = (path: string, size = 'w342') =>
  `https://image.tmdb.org/t/p/${size}/${path}.jpg`
const openLibrary = (isbn: string) =>
  `https://covers.openlibrary.org/b/isbn/${isbn}-M.jpg`
const coverArt = (releaseGroup: string) =>
  `https://coverartarchive.org/release-group/${releaseGroup}/front-250`

export type Cover = { title: string; url: string }

/** A cover drawn in type, for kinds with no open catalog artwork. */
export type TypeTile = { title: string; caption: string }

export type KindCard = {
  id: string
  name: string
  pitch: string
  /** 2:3 covers, or 1:1 for music. */
  shape: 'poster' | 'square'
  covers: Array<Cover | TypeTile>
}

/** The hero's fan of posters, left to right. The middle of the list sits in the middle. */
export const FAN: Cover[] = [
  { title: 'Spirited Away', url: tmdb('39wmItIWsg5sZMyRUHLkWBcuVCM') },
  { title: 'The Office', url: tmdb('7DJKHzAi83BmQrWLrYYOqcoKfhR') },
  { title: 'Dune', url: openLibrary('9780441172719') },
  { title: 'Frieren', url: tmdb('dqZENchTd7lp5zht7BdlqM7RBhD') },
  { title: 'Interstellar', url: tmdb('gEU2QniE6E77NI6lCU6MxlNBvIx') },
  { title: 'Severance', url: tmdb('lFf6LLrQjYldcZItzOkGmMMigP7') },
  {
    title: 'Everything Everywhere All at Once',
    url: tmdb('w3LxiVYdWWRvEVdn5RYq6jIqkb1'),
  },
  { title: 'Breaking Bad', url: tmdb('ztkUQFLlC19CCMYHW9o1zWhJRNq') },
  { title: 'Cowboy Bebop', url: tmdb('xDiXDfZwC6XYC6fxHI1jl3A3Ill') },
  { title: 'Project Hail Mary', url: openLibrary('9780593135204') },
  { title: 'Parasite', url: tmdb('7IiTTgloJzvGI1TAYymCfbfl3vT') },
  { title: 'The Bear', url: tmdb('sHFlbKS3WLqMnp9t2ghADIJFnuQ') },
  { title: 'Spy x Family', url: tmdb('3r4LYFuXrg3G8fepysr4xSLWnQL') },
]

export const KIND_CARDS: KindCard[] = [
  {
    id: 'shows',
    name: 'TV shows',
    pitch: 'Tick episodes, see what airs this week, never lose your place.',
    shape: 'poster',
    covers: [
      {
        title: 'Stranger Things',
        url: tmdb('49WJfeN0moxb9IPfGn8AIqMGskD', 'w185'),
      },
      {
        title: 'Game of Thrones',
        url: tmdb('1XS1oqL89opfnbLl8WnZY1O1uJx', 'w185'),
      },
      { title: 'Severance', url: tmdb('lFf6LLrQjYldcZItzOkGmMMigP7', 'w185') },
    ],
  },
  {
    id: 'movies',
    name: 'Movies',
    pitch: 'What you have seen, what you mean to, and what you thought of it.',
    shape: 'poster',
    covers: [
      {
        title: 'Pulp Fiction',
        url: tmdb('d5iIlFn5s0ImszYzBPb8JPIfbXD', 'w185'),
      },
      {
        title: 'Dune: Part Two',
        url: tmdb('1pdfLvkbY9ohJlCjQH2CZjjYVvJ', 'w185'),
      },
      {
        title: 'Oppenheimer',
        url: tmdb('8Gxv8gSFCU0XGDykEGv7zR1n2ua', 'w185'),
      },
    ],
  },
  {
    id: 'anime',
    name: 'Anime',
    pitch:
      'First-class, season by season, with your MyAnimeList and AniList history.',
    shape: 'poster',
    covers: [
      { title: 'Death Note', url: tmdb('tCZFfYTIwrR7n94J6G14Y4hAFU6', 'w185') },
      {
        title: 'Jujutsu Kaisen',
        url: tmdb('fHpKWq9ayzSk8nSwqRuaAUemRKh', 'w185'),
      },
      {
        title: 'Fullmetal Alchemist: Brotherhood',
        url: tmdb('5ZFUEOULaVml7pQuXxhpR2SmVUw', 'w185'),
      },
    ],
  },
  {
    id: 'books',
    name: 'Books',
    pitch:
      'Your reading pile and everything you have finished, Goodreads included.',
    shape: 'poster',
    covers: [
      { title: 'Piranesi', url: openLibrary('9781635575637') },
      { title: 'Project Hail Mary', url: openLibrary('9780593135204') },
      { title: 'The Midnight Library', url: openLibrary('9780525559474') },
    ],
  },
  {
    id: 'music',
    name: 'Music',
    pitch:
      'The albums you keep coming back to, and the ones still on your list.',
    shape: 'square',
    covers: [
      {
        title: 'Rumours',
        url: coverArt('416bb5e5-c7d1-3977-8fd7-7c9daf6c2be6'),
      },
      {
        title: 'Random Access Memories',
        url: coverArt('aa997ea0-2936-40bd-884d-3af8a0e064dc'),
      },
      {
        title: 'Kind of Blue',
        url: coverArt('8e8a594f-2175-38c7-a871-abb68ec363e7'),
      },
    ],
  },
  {
    id: 'sports',
    name: 'Sports',
    pitch:
      'The seasons, races and matches you follow, next to everything else.',
    shape: 'poster',
    covers: [
      { title: 'F1', caption: 'Season' },
      { title: 'Premier League', caption: 'Matchday' },
      { title: 'NBA', caption: 'Playoffs' },
    ],
  },
]
