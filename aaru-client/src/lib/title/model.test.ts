import { describe, expect, it } from 'vitest'
import { airedKeys, episodeKey, nextRating, orderedSeasons } from './model'
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
        { season: 1, number: 1, airTimeKnown: false, airsAt: '2026-01-01T00:00:00Z' },
        { season: 1, number: 2, airTimeKnown: false, airsAt: '2099-01-01T00:00:00Z' },
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
})
