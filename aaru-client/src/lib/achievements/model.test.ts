import { describe, expect, it } from 'vitest'
import {
  badgeName,
  byFamily,
  earnedLine,
  levelFraction,
  nextLevelLine,
  pointsDelta,
  pointsKind,
  progressFraction,
  progressText,
  revealOf,
  streakHint,
  streakLine,
  tierName,
  unlockSummary,
  weekRange,
  weekdayLetter,
} from './model'
import type { Badge, BadgeAward, Progress } from './model'
import { validTimeZone } from '../timezone'

const badge = (over: Partial<Badge>): Badge => ({
  id: 'films',
  family: 'films',
  hidden: false,
  earned: false,
  tier: 0,
  maxTier: 4,
  name: 'Cinephile',
  ...over,
})

const award = (over: Partial<BadgeAward>): BadgeAward => ({
  id: '00000000-0000-0000-0000-000000000001',
  badge: 'night_owl',
  name: 'Night Owl',
  family: 'streaks',
  tier: 1,
  maxTier: 3,
  awardedAt: '2026-10-22T23:10:00Z',
  origin: 'live',
  reveal: false,
  ...over,
})

const unseen = (over: Partial<Progress['unseen']>): Progress['unseen'] => ({
  count: 0,
  origin: 'live',
  items: [],
  ...over,
})

const progress = (over: Partial<Progress>): Progress => ({
  total: 0,
  level: 1,
  levelStart: 0,
  nextLevelAt: 100,
  weekPoints: 0,
  streak: { current: 0, longest: 0, today: false, days: [] },
  unseen: unseen({}),
  ...over,
})

describe('achievements model', () => {
  it('names tiers bronze to platinum, and none for a one-tier badge', () => {
    expect(tierName(1, 4)).toBe('Bronze')
    expect(tierName(4, 4)).toBe('Platinum')
    expect(tierName(3, 3)).toBe('Gold')
    expect(tierName(1, 1)).toBeNull()
    expect(tierName(0, 4)).toBeNull()
  })

  it('shows progress as "62 / 100" and nothing once complete', () => {
    expect(
      progressText(badge({ progress: { current: 62, target: 100 } })),
    ).toBe('62 / 100')
    expect(
      progressText(badge({ progress: { current: 1200, target: 5000 } })),
    ).toBe('1,200 / 5,000')
    expect(progressText(badge({ earned: true, tier: 4 }))).toBeNull()
    expect(
      progressFraction(badge({ progress: { current: 62, target: 100 } })),
    ).toBe(0.62)
    expect(progressFraction(badge({ earned: true, tier: 4 }))).toBe(1)
  })

  it('keeps a hidden badge as ??? until it is earned', () => {
    expect(badgeName(badge({ hidden: true, name: undefined }))).toBe('???')
    expect(
      badgeName(badge({ hidden: true, earned: true, name: 'Long Haul' })),
    ).toBe('Long Haul')
  })

  it('groups by family in display order, earned first', () => {
    const groups = byFamily([
      badge({ id: 'pilot', family: 'shows' }),
      badge({ id: 'films' }),
      badge({ id: 'first_film', earned: true, tier: 1 }),
    ])
    expect(groups.map((g) => g.label)).toEqual(['Films', 'Shows'])
    expect(groups[0]?.badges.map((b) => b.id)).toEqual(['first_film', 'films'])
    expect(earnedLine([badge({ earned: true }), badge({})])).toBe(
      '1 of 2 earned',
    )
  })

  it('measures the way to the next level', () => {
    const p = progress({
      total: 130,
      level: 2,
      levelStart: 100,
      nextLevelAt: 300,
    })
    expect(levelFraction(p)).toBe(0.15)
    expect(nextLevelLine(p)).toBe('170 points to level 3')
    expect(nextLevelLine(progress({ total: 99 }))).toBe('1 point to level 2')
  })

  it('words the streak calmly', () => {
    expect(streakLine({ current: 0, longest: 0, today: false, days: [] })).toBe(
      'Watch or read something to start a streak',
    )
    expect(streakLine({ current: 0, longest: 9, today: false, days: [] })).toBe(
      'Longest streak: 9 days',
    )
    expect(streakLine({ current: 1, longest: 1, today: true, days: [] })).toBe(
      '1 day in a row',
    )
    expect(streakHint({ current: 3, longest: 3, today: false, days: [] })).toBe(
      'Today is still open',
    )
    expect(
      streakHint({ current: 0, longest: 3, today: false, days: [] }),
    ).toBeNull()
    expect(weekdayLetter('2026-10-22')).toBe('T')
    expect(weekdayLetter('2026-10-25')).toBe('S')
  })

  it('collapses unseen badges into one line, and one summary for an import or the first run', () => {
    expect(unlockSummary(unseen({}))).toBeNull()
    expect(unlockSummary(unseen({ count: 1, items: [award({})] }))).toBe(
      'Night Owl · earned',
    )
    expect(unlockSummary(unseen({ count: 3, items: [award({})] }))).toBe(
      '3 badges earned',
    )
    expect(unlockSummary(unseen({ count: 14, origin: 'batch' }))).toBe(
      'Your history earned you 14 badges.',
    )
    expect(unlockSummary(unseen({ count: 14, origin: 'backfill' }))).toBe(
      'Aaru gives badges now. You’ve already earned 14.',
    )
  })

  it('reveals only a live top tier', () => {
    const top = award({ tier: 3, reveal: true })
    expect(revealOf(unseen({ count: 2, items: [award({}), top] }))).toBe(top)
    expect(
      revealOf(unseen({ count: 1, origin: 'batch', items: [top] })),
    ).toBeNull()
    expect(revealOf(unseen({ count: 1, items: [award({})] }))).toBeNull()
  })

  it('labels ledger rows', () => {
    expect(pointsKind('season_bonus')).toBe('Season complete')
    expect(pointsKind('something_new')).toBe('Points')
    expect(pointsDelta(10)).toBe('+10')
    expect(pointsDelta(-25)).toBe('−25')
  })

  it('writes the week as a short range', () => {
    expect(weekRange('2026-10-19', '2026-10-25')).toBe('Oct 19 – 25')
    expect(weekRange('2026-10-26', '2026-11-01')).toBe('Oct 26 – Nov 1')
  })
})

describe('time zone cookie', () => {
  it('accepts IANA zones and nothing else', () => {
    expect(validTimeZone('Europe/Lisbon')).toBe('Europe/Lisbon')
    expect(validTimeZone('UTC')).toBe('UTC')
    expect(validTimeZone('Mars/Olympus')).toBeNull()
    expect(validTimeZone('Europe/Lisbon; drop')).toBeNull()
    expect(validTimeZone('')).toBeNull()
    expect(validTimeZone(undefined)).toBeNull()
  })
})
