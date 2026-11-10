import { describe, expect, it } from 'vitest'
import {
  canHost,
  countdownSeconds,
  hitRef,
  kindGlyph,
  markLabel,
  partyPhase,
  partyTarget,
  partyWord,
  readingTarget,
  phaseLabel,
  progressLabel,
  reactionDue,
  serverOffset,
  spoilerChoiceLabel,
  spoilerFields,
  stampLabel,
  validEpisode,
} from './kinds'
import type { WatchParty } from './kinds'

const party = (extra: Partial<WatchParty> = {}): WatchParty => ({
  id: 'p',
  title: {
    id: 't',
    type: 'show',
    title: 'Shogun',
    isAnime: false,
    ids: {},
  },
  state: 'lobby',
  ready: [],
  host: { userId: 'h', handle: 'host' },
  ...extra,
})

describe('kind glyphs', () => {
  it('keeps # for chat and marks the others', () => {
    expect(kindGlyph('text')).toBe('#')
    expect(
      new Set(['title', 'watch', 'shelf'].map((k) => kindGlyph(k as never)))
        .size,
    ).toBe(3)
  })
})

describe('spoiler control', () => {
  it('sends nothing for auto, so the server stamps my progress', () => {
    expect(spoilerFields({ mode: 'auto' })).toEqual({})
  })

  it('maps each hand choice to the request fields', () => {
    expect(spoilerFields({ mode: 'free' })).toEqual({ spoilerFree: true })
    expect(spoilerFields({ mode: 'ending' })).toEqual({
      spoiler: { ending: true },
    })
    expect(spoilerFields({ mode: 'episode', season: 1, episode: 5 })).toEqual({
      spoiler: { season: 1, episode: 5 },
    })
  })

  it('labels the chip', () => {
    expect(spoilerChoiceLabel({ mode: 'auto' })).toBe('Marked at your progress')
    expect(spoilerChoiceLabel({ mode: 'episode', season: 2, episode: 1 })).toBe(
      'Spoils up to S2 · E1',
    )
  })

  it('accepts specials but not episode zero or fractions', () => {
    expect(validEpisode(0, 1)).toBe(true)
    expect(validEpisode(1, 0)).toBe(false)
    expect(validEpisode(1.5, 2)).toBe(false)
  })

  it('tags my own stamps', () => {
    expect(stampLabel({ season: 1, episode: 3 })).toBe('S1 · E3')
    expect(stampLabel({ ending: true })).toBe('Ending')
    expect(stampLabel(undefined)).toBeNull()
  })
})

describe('progress labels', () => {
  const user = { userId: 'u', handle: 'u' }
  it('reads where someone is', () => {
    expect(progressLabel({ user })).toBe('Not started')
    expect(
      progressLabel({ user, status: 'finished', season: 2, episode: 9 }),
    ).toBe('Finished')
    expect(
      progressLabel({ user, status: 'in_progress', season: 1, episode: 3 }),
    ).toBe('S1 · E3')
    expect(progressLabel({ user, status: 'wishlist' })).toBe('Planned')
    expect(progressLabel({ user, status: 'wishlist' }, 'show')).toBe(
      'Plan to watch',
    )
    expect(progressLabel({ user, status: 'finished' }, 'show')).toBe('Watched')
    expect(progressLabel({ user, status: 'finished' }, 'book')).toBe('Read')
  })
})

describe('watch party clock', () => {
  it('measures how far the server clock is ahead', () => {
    expect(
      serverOffset('2026-10-20T10:00:02Z', Date.parse('2026-10-20T10:00:00Z')),
    ).toBe(2000)
    expect(serverOffset('nonsense', 0)).toBe(0)
  })

  it('counts down against the server clock, rounding up', () => {
    const startsAt = '2026-10-20T10:00:10Z'
    const local = Date.parse('2026-10-20T10:00:00Z')
    expect(countdownSeconds(startsAt, local, 0)).toBe(10)
    // The server is 3 s ahead: 7 s left, whatever this device thinks.
    expect(countdownSeconds(startsAt, local, 3000)).toBe(7)
    expect(countdownSeconds(startsAt, local + 9100, 0)).toBe(1)
    expect(countdownSeconds(startsAt, local + 10_000, 0)).toBe(0)
  })

  it('turns a countdown live on its own and keeps an ended party ended', () => {
    const local = Date.parse('2026-10-20T10:00:00Z')
    expect(partyPhase(party(), local, 0)).toBe('lobby')
    const counting = party({
      state: 'countdown',
      startsAt: '2026-10-20T10:00:05Z',
    })
    expect(partyPhase(counting, local, 0)).toBe('countdown')
    expect(partyPhase(counting, local + 6000, 0)).toBe('live')
    expect(
      partyPhase(
        party({ state: 'ended', endedAt: '2026-10-20T11:00:00Z' }),
        local,
        0,
      ),
    ).toBe('ended')
    expect(phaseLabel('live')).toBe('Playing now')
  })

  it('lets the host and admins run the party', () => {
    expect(canHost(party(), 'h', 'member')).toBe(true)
    expect(canHost(party(), 'x', 'admin')).toBe(true)
    expect(canHost(party(), 'x', 'member')).toBe(false)
  })

  it('sends a reaction at most once a second', () => {
    expect(reactionDue(undefined, 0)).toBe(true)
    expect(reactionDue(1000, 1500)).toBe(false)
    expect(reactionDue(1000, 2000)).toBe(true)
  })
})

describe('hitRef', () => {
  it('carries provider ids, title and year', () => {
    expect(
      hitRef({
        type: 'movie',
        title: 'Arrival',
        year: 2016,
        isAnime: false,
        ids: { tmdb: '1' },
      }),
    ).toEqual({
      type: 'movie',
      ids: { tmdb: '1' },
      title: 'Arrival',
      year: 2016,
    })
  })
})

describe('sessions that read (ROOM-005)', () => {
  it('calls a book or manga party a reading session', () => {
    expect(partyWord('manga')).toBe('Reading session')
    expect(partyWord('book')).toBe('Reading session')
    expect(partyWord('show')).toBe('Watch party')
    expect(partyWord('movie')).toBe('Watch party')
  })

  it('says what a party is aimed at', () => {
    expect(partyTarget(party({ season: 1, episode: 3 }))).toBe('S1 · E3')
    expect(partyTarget(party({ chapter: 12, volume: 2 }))).toBe(
      'Chapter 12 · Vol. 2',
    )
    expect(partyTarget(party({ volume: 2 }))).toBe('Vol. 2')
    expect(partyTarget(party({ page: 120 }))).toBe('Page 120')
    expect(partyTarget(party())).toBeNull()
  })

  it('words the tap in the kind’s own verb', () => {
    expect(markLabel('show')).toBe('Mark watched for me')
    expect(markLabel('book')).toBe('Mark read for me')
    expect(markLabel('manga')).toBe('Mark read for me')
    expect(markLabel('album')).toBe('Mark listened for me')
  })

  it('reads the opening form into a target, leaving blanks out', () => {
    const blank = { chapter: '', volume: '', page: '' }
    expect(readingTarget('manga', { ...blank, chapter: '12' })).toEqual({
      chapter: 12,
    })
    expect(
      readingTarget('manga', { chapter: '12', volume: '2', page: '9' }),
    ).toEqual({ chapter: 12, volume: 2 })
    expect(readingTarget('book', { ...blank, page: '120' })).toEqual({
      page: 120,
    })
    expect(readingTarget('book', blank)).toEqual({})
    // A film has no reading target, whatever the fields hold.
    expect(readingTarget('movie', { ...blank, page: '3' })).toEqual({})
    expect(readingTarget('manga', { ...blank, chapter: '-1' })).toBeNull()
    expect(readingTarget('book', { ...blank, page: '1.5' })).toBeNull()
  })
})
