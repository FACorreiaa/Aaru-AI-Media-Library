import { describe, expect, it } from 'vitest'
import {
  countTiles,
  genreBars,
  heroLine,
  isEmptyProfile,
  memberSince,
  timeShares,
  timeSpent,
} from './model'
import type { ProfileStats } from './model'
import { initials } from './initials'

const none = { wishlist: 0, inProgress: 0, finished: 0, dropped: 0 }

function stats(overrides: Partial<ProfileStats> = {}): ProfileStats {
  return {
    memberSince: '2026-10-02T09:00:00Z',
    episodesWatched: 4812,
    minutesWatched: 59_400 + 6 * 60,
    pagesRead: 0,
    shows: { ...none, finished: 12, inProgress: 3 },
    anime: { ...none, finished: 4 },
    movies: { ...none, finished: 40 },
    books: { ...none, finished: 2 },
    byKind: [
      { kind: 'movie', episodes: 0, minutes: 6000, finished: 40 },
      { kind: 'show', episodes: 4000, minutes: 48_000, finished: 12 },
      { kind: 'anime', episodes: 812, minutes: 0, finished: 4 },
      { kind: 'book', episodes: 0, minutes: 0, finished: 2 },
    ],
    topGenres: [],
    topNetworks: [],
    mostWatched: [],
    ratings: { count: 0, distribution: [] },
    ...overrides,
  }
}

describe('timeSpent', () => {
  it('reads days and hours, the way MyAnimeList counts time', () => {
    expect(timeSpent(41 * 1440 + 6 * 60 + 20)).toBe('41 days, 6 hours')
    expect(timeSpent(1440)).toBe('1 day')
    expect(timeSpent(1440 + 60)).toBe('1 day, 1 hour')
    expect(timeSpent(6 * 60 + 59)).toBe('6 hours')
    expect(timeSpent(45)).toBe('45 minutes')
    expect(timeSpent(0)).toBe('0 minutes')
  })
})

describe('heroLine', () => {
  it('gives hours and episodes, leaving out what is zero', () => {
    expect(heroLine(stats())).toBe('996 hours · 4,812 episodes')
    expect(heroLine(stats({ minutesWatched: 30, episodesWatched: 1 }))).toBe(
      '1 episode',
    )
    expect(heroLine(stats({ minutesWatched: 0, episodesWatched: 0 }))).toBe('')
  })
})

describe('initials', () => {
  it('takes two words, one, or the handle', () => {
    expect(initials({ displayName: 'Ana Lopes', handle: 'ana' })).toBe('AL')
    expect(initials({ displayName: 'ana', handle: 'x' })).toBe('A')
    expect(initials({ displayName: null, handle: 'reed' })).toBe('R')
    expect(initials({ displayName: '  ', handle: null })).toBeNull()
  })
})

describe('memberSince', () => {
  it('names the month and year', () => {
    expect(memberSince('2026-10-02T09:00:00Z')).toBe('In Aaru since Oct 2026')
    expect(memberSince(undefined)).toBeNull()
  })
})

describe('countTiles', () => {
  it('counts finished titles per kind, with what is going on series', () => {
    const tiles = countTiles(stats({ pagesRead: 4210 }))
    expect(tiles.map((t) => [t.label, t.value, t.detail])).toEqual([
      ['Shows watched', 12, '3 watching'],
      ['Anime watched', 4, undefined],
      ['Films watched', 40, undefined],
      ['Books read', 2, '4,210 pages'],
    ])
    expect(tiles.map((t) => t.kind)).toEqual(['show', 'anime', 'film', 'book'])
    expect(tiles.every((t) => t.status === 'finished')).toBe(true)
  })
})

describe('timeShares', () => {
  it('splits TV, anime and films, leaving out a kind without time', () => {
    expect(timeShares(stats())).toEqual([
      { kind: 'show', label: 'TV', minutes: 48_000, share: 48_000 / 54_000 },
      { kind: 'movie', label: 'Films', minutes: 6000, share: 6000 / 54_000 },
    ])
    expect(timeShares(stats({ byKind: [] }))).toEqual([])
  })
})

describe('genreBars', () => {
  it('draws the top genre full width and the rest against it', () => {
    expect(
      genreBars([
        { name: 'Drama', minutes: 600, titles: 9 },
        { name: 'Comedy', minutes: 150, titles: 1 },
      ]),
    ).toEqual([
      { name: 'Drama', width: 1, time: '10 h', titles: '9 titles' },
      { name: 'Comedy', width: 0.25, time: '3 h', titles: '1 title' },
    ])
    expect(genreBars([])).toEqual([])
  })
})

describe('isEmptyProfile', () => {
  it('is empty until something is watched, finished or rated', () => {
    expect(isEmptyProfile(stats())).toBe(false)
    const blank = stats({
      episodesWatched: 0,
      minutesWatched: 0,
      shows: none,
      anime: none,
      movies: none,
      books: none,
    })
    expect(isEmptyProfile(blank)).toBe(true)
    expect(
      isEmptyProfile({ ...blank, ratings: { count: 1, distribution: [] } }),
    ).toBe(false)
  })
})
