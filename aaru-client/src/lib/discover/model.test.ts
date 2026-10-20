import { describe, expect, it } from 'vitest'
import { cardBadge, releaseBadge, sectionTitle } from './model'

describe('section titles', () => {
  it('names the fixed sections', () => {
    expect(sectionTitle({ id: 'trending' })).toBe('Trending this week')
    expect(sectionTitle({ id: 'upcoming_movies' })).toBe('Coming to cinemas')
    expect(sectionTitle({ id: 'new_shows' })).toBe('New shows')
    expect(sectionTitle({ id: 'on_the_air' })).toBe('Airing this week')
  })

  it('names anime sections by their season', () => {
    expect(
      sectionTitle({
        id: 'anime_season',
        animeSeason: { season: 'fall', year: 2026 },
      }),
    ).toBe('Anime · Fall 2026')
    expect(
      sectionTitle({
        id: 'anime_next_season',
        animeSeason: { season: 'winter', year: 2027 },
      }),
    ).toBe('Anime · Winter 2027')
  })

  it('keeps a plain name when the season is missing', () => {
    expect(sectionTitle({ id: 'anime_season' })).toBe('Anime this season')
  })
})

describe('release badge', () => {
  const today = '2026-10-20'

  it('reads relative days close by', () => {
    expect(releaseBadge('2026-10-19', today)).toBe('Out now')
    expect(releaseBadge('2026-10-20', today)).toBe('Today')
    expect(releaseBadge('2026-10-21', today)).toBe('Tomorrow')
    expect(releaseBadge('2026-10-23', today)).toBe('In 3 days')
  })

  it('reads a date further out, with the year only when it differs', () => {
    expect(releaseBadge('2026-11-14', today)).toBe('Nov 14')
    expect(releaseBadge('2027-01-03', today)).toBe('Jan 3, 2027')
  })

  it('has no badge without a usable date', () => {
    expect(releaseBadge(undefined, today)).toBeNull()
    expect(releaseBadge('2026', today)).toBeNull()
  })

  it('says "Out now" only for films coming to cinemas', () => {
    expect(cardBadge('upcoming_movies', '2026-10-01', today)).toBe('Out now')
    expect(cardBadge('trending', '2026-10-01', today)).toBeNull()
    expect(cardBadge('new_shows', '2026-10-27', today)).toBe('Oct 27')
  })
})
