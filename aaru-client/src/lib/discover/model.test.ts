import { describe, expect, it } from 'vitest'
import { cardBadge, releaseBadge } from './model'

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

  it('says "Out now" only on the in-theaters row', () => {
    expect(cardBadge('movies_in_theaters', '2026-10-01', today)).toBe('Out now')
    expect(cardBadge('movies_trending', '2026-10-01', today)).toBeNull()
    expect(cardBadge('tv_new', '2026-10-27', today)).toBe('Oct 27')
  })

  it('treats a row id it does not know like any other row', () => {
    expect(cardBadge('music_new', '2026-10-01', today)).toBeNull()
    expect(cardBadge('music_new', '2026-10-21', today)).toBe('Tomorrow')
  })
})
