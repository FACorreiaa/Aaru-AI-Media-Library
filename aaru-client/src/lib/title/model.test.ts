import { describe, expect, it } from 'vitest'
import {
  airedKeys,
  cellState,
  episodeKey,
  neighbours,
  nextEpisode,
  nextRating,
  ratingLabel,
  orderedSeasons,
  episodeCode,
  showStatusLabel,
} from './model'
import type { TitleDetail } from './model'

const title: TitleDetail = {
  id: 't',
  type: 'show',
  title: 'Show',
  isAnime: false,
  ids: {},
  seasons: [
    { number: 0, episodes: [{ season: 0, number: 1, airTimeKnown: false }] },
    {
      number: 1,
      episodes: [
        {
          season: 1,
          number: 1,
          airTimeKnown: false,
          airsAt: '2026-01-01T00:00:00Z',
        },
        {
          season: 1,
          number: 2,
          airTimeKnown: false,
          airsAt: '2099-01-01T00:00:00Z',
        },
        { season: 1, number: 3, airTimeKnown: false },
      ],
    },
  ],
}

describe('title model', () => {
  it('marks only aired episodes of a season (no date counts as aired)', () => {
    expect(airedKeys(title, 1, new Date('2026-10-15T00:00:00Z'))).toEqual([
      episodeKey(1, 1),
      episodeKey(1, 3),
    ])
  })

  it('puts specials after the numbered seasons', () => {
    expect(orderedSeasons(title).map((s) => s.number)).toEqual([1, 0])
  })

  it('rates in two-point stars, and the same star clears', () => {
    expect(nextRating(undefined, 4)).toBe(8)
    expect(nextRating(8, 4)).toBeNull()
  })

  it('names the rating with its value', () => {
    expect(ratingLabel(8)).toBe('Rating, 8 of 10')
    expect(ratingLabel(7)).toBe('Rating, 7 of 10')
    expect(ratingLabel(undefined)).toBe('Rating, not rated')
  })

  const now = new Date('2026-10-15T00:00:00Z')

  it('picks up at the first aired, unwatched episode, never a special', () => {
    expect(nextEpisode(title, new Set(), now)?.number).toBe(1)
    expect(nextEpisode(title, new Set([episodeKey(1, 1)]), now)?.number).toBe(3)
    const all = new Set([episodeKey(1, 1), episodeKey(1, 3)])
    expect(nextEpisode(title, all, now)).toBeUndefined()
  })

  it('colours cells watched, next, aired or unaired', () => {
    const [first, unaired, undated] = title.seasons![1].episodes
    const watched = new Set([episodeKey(1, 1)])
    const next = nextEpisode(title, watched, now)
    expect(cellState(first, watched, next, now)).toBe('watched')
    expect(cellState(undated, watched, next, now)).toBe('next')
    expect(cellState(unaired, watched, next, now)).toBe('unaired')
    expect(
      cellState(undated, new Set(), nextEpisode(title, new Set(), now), now),
    ).toBe('aired')
  })

  it('steps through episodes in viewing order, across seasons into specials', () => {
    expect(neighbours(title, 1, 1).previous).toBeUndefined()
    expect(neighbours(title, 1, 2).next?.number).toBe(3)
    expect(neighbours(title, 1, 3).next?.season).toBe(0)
    expect(neighbours(title, 9, 9)).toEqual({})
  })
})

describe('showStatusLabel', () => {
  it('names each status as the Apple apps do', () => {
    expect(showStatusLabel('returning')).toBe('Returning')
    expect(showStatusLabel('canceled')).toBe('Canceled')
    expect(showStatusLabel(undefined)).toBeUndefined()
  })
})

describe('episodeCode', () => {
  it('reads S1 · E8, and Special for season 0', () => {
    expect(episodeCode(1, 8)).toBe('S1 · E8')
    expect(episodeCode(0, 2)).toBe('Special 2')
  })
})
