import { describe, expect, it } from 'vitest'
import {
  LIVE_REFRESH_MS,
  PENDING_MAX_TRIES,
  PENDING_RETRY_MS,
  addDays,
  clockLabel,
  dayName,
  dayStrip,
  entityLine,
  eventTitle,
  favoritesState,
  groupBroadcasts,
  hasScore,
  inStrip,
  isCard,
  placeLine,
  refreshDelay,
  scheduleState,
  sportQuery,
  statusLabel,
  whenLine,
} from './model'
import type { SportEvent, SportFavorite } from './model'
import { countries, countryName, isCountryCode, regionOf } from './countries'

const event = (over: Partial<SportEvent> = {}): SportEvent => ({
  id: 'e1',
  sport: 'Soccer',
  name: 'Arsenal vs Chelsea',
  home: { name: 'Arsenal', score: 2 },
  away: { name: 'Chelsea', score: 1 },
  startsAt: '2026-10-24T19:45:00Z',
  day: '2026-10-24',
  status: 'scheduled',
  isFavorite: false,
  ...over,
})

describe('day math', () => {
  it('adds and takes days across months, years and a leap day', () => {
    expect(addDays('2026-10-24', 1)).toBe('2026-10-25')
    expect(addDays('2026-10-31', 1)).toBe('2026-11-01')
    expect(addDays('2026-01-01', -1)).toBe('2025-12-31')
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29')
    expect(addDays('2026-03-28', 2)).toBe('2026-03-30')
  })

  it('leaves what is not a day alone', () => {
    expect(addDays('2026-02-30', 1)).toBe('2026-02-30')
    expect(addDays('soon', 1)).toBe('soon')
  })
})

describe('date strip', () => {
  const strip = dayStrip('2026-10-24')

  it('runs three days back to a week ahead, Today marked', () => {
    expect(strip).toHaveLength(11)
    expect(strip[0].key).toBe('2026-10-21')
    expect(strip[10].key).toBe('2026-10-31')
    expect(strip.filter((d) => d.isToday).map((d) => d.key)).toEqual([
      '2026-10-24',
    ])
  })

  it('names the days around today and the weekday for the rest', () => {
    expect(strip.map((d) => d.name).slice(0, 6)).toEqual([
      'Wed',
      'Thu',
      'Yesterday',
      'Today',
      'Tomorrow',
      'Mon',
    ])
    expect(strip[3].date).toBe('24 Oct')
    expect(strip[3].label).toBe('Today, Saturday 24 October')
    expect(strip[0].label).toBe('Wednesday 21 October')
  })

  it('crosses a month', () => {
    expect(dayStrip('2026-10-30').at(-1)?.date).toBe('6 Nov')
  })

  it('knows which days are on it', () => {
    expect(inStrip('2026-10-21', '2026-10-24')).toBe(true)
    expect(inStrip('2026-10-20', '2026-10-24')).toBe(false)
    expect(inStrip('2026-10-31', '2026-10-24')).toBe(true)
    expect(inStrip('2026-11-01', '2026-10-24')).toBe(false)
  })
})

describe('when', () => {
  it('names a day from today', () => {
    expect(dayName('2026-10-24', '2026-10-24')).toBe('Today')
    expect(dayName('2026-10-25', '2026-10-24')).toBe('Tomorrow')
    expect(dayName('2026-10-23', '2026-10-24')).toBe('Yesterday')
    expect(dayName('2026-10-28', '2026-10-24')).toBe('Wed 28 Oct')
    expect(dayName('2027-01-02', '2026-10-24')).toBe('Sat 2 Jan 2027')
  })

  it('reads the start in the viewer’s zone', () => {
    const late = event({ startsAt: '2026-10-24T23:30:00Z' })
    expect(whenLine(late, '2026-10-24', 'Europe/London')).toBe(
      'Tomorrow · 00:30',
    )
    expect(whenLine(late, '2026-10-24', 'America/New_York')).toBe(
      'Today · 19:30',
    )
    expect(whenLine({ day: '2026-10-26' }, '2026-10-24')).toBe('Mon 26 Oct')
  })
})

describe('status', () => {
  it('reads the live clock', () => {
    expect(clockLabel('67')).toBe('67′')
    expect(clockLabel('45+2')).toBe('45+2′')
    expect(clockLabel('HT')).toBe('HT')
    expect(clockLabel('Q3')).toBe('Q3')
    expect(clockLabel(' ')).toBeNull()
    expect(clockLabel(undefined)).toBeNull()
  })

  it('says Live with the clock, FT or Final, Postponed, Cancelled', () => {
    expect(statusLabel(event({ status: 'live', progress: '67' }))).toBe(
      'Live · 67′',
    )
    expect(statusLabel(event({ status: 'live' }))).toBe('Live')
    expect(statusLabel(event({ status: 'finished' }))).toBe('FT')
    expect(
      statusLabel(event({ status: 'finished', sport: 'Basketball' })),
    ).toBe('Final')
    expect(statusLabel(event({ status: 'postponed' }))).toBe('Postponed')
    expect(statusLabel(event({ status: 'cancelled' }))).toBe('Cancelled')
  })

  it('shows the kick-off in the viewer’s zone, TBA without one', () => {
    expect(statusLabel(event(), 'Europe/Lisbon')).toBe('20:45')
    expect(statusLabel(event(), 'Asia/Tokyo')).toBe('04:45')
    expect(statusLabel(event({ startsAt: undefined }))).toBe('TBA')
  })

  it('shows a score only when the game is on or over', () => {
    expect(hasScore(event({ status: 'live' }))).toBe(true)
    expect(hasScore(event({ status: 'finished' }))).toBe(true)
    expect(hasScore(event())).toBe(false)
    expect(hasScore(event({ status: 'live', away: { name: 'Chelsea' } }))).toBe(
      false,
    )
  })
})

describe('cards and lines', () => {
  const card = event({
    sport: 'Fighting',
    name: 'UFC 333 Volkanovski vs Evloev',
    home: undefined,
    away: undefined,
  })

  it('treats a UFC or WWE event as a card by its own name', () => {
    expect(isCard(card)).toBe(true)
    expect(isCard(event())).toBe(false)
    expect(eventTitle(card)).toBe('UFC 333 Volkanovski vs Evloev')
    expect(eventTitle(event())).toBe('Arsenal v Chelsea')
  })

  it('joins venue and round', () => {
    expect(placeLine({ venue: 'Emirates Stadium', round: '9' })).toBe(
      'Emirates Stadium · Round 9',
    )
    expect(placeLine({ round: 'Quarter-final' })).toBe('Quarter-final')
    expect(placeLine({ venue: ' ' })).toBeNull()
  })

  it('names an entity’s sport with its country, or a player’s team', () => {
    expect(
      entityLine({
        kind: 'league',
        id: '4328',
        name: 'Premier League',
        sport: 'Soccer',
        country: 'England',
        following: false,
      }),
    ).toBe('Soccer · England')
    expect(
      entityLine({
        kind: 'player',
        id: '1',
        name: 'Mbappé',
        sport: 'Soccer',
        country: 'France',
        teamName: 'Real Madrid',
        following: true,
      }),
    ).toBe('Soccer · Real Madrid')
  })

  it('searches from two characters to a hundred', () => {
    expect(sportQuery(' a ')).toBeNull()
    expect(sportQuery('  nba ')).toBe('nba')
    expect(sportQuery('x'.repeat(101))).toBeNull()
  })
})

describe('where to watch', () => {
  it('groups by country, A to Z, channels without one last, no repeats', () => {
    expect(
      groupBroadcasts([
        { channel: 'Sky Sports', country: 'United Kingdom' },
        { channel: 'ESPN', country: 'United States' },
        { channel: 'TNT Sports', country: 'United Kingdom' },
        { channel: 'Sky Sports ', country: 'United Kingdom' },
        { channel: 'DAZN' },
        { channel: 'Sport TV', country: 'Portugal' },
        { channel: ' ', country: 'Spain' },
      ]),
    ).toEqual([
      {
        country: 'Portugal',
        channels: [{ channel: 'Sport TV', country: 'Portugal' }],
      },
      {
        country: 'United Kingdom',
        channels: [
          { channel: 'Sky Sports', country: 'United Kingdom' },
          { channel: 'TNT Sports', country: 'United Kingdom' },
        ],
      },
      {
        country: 'United States',
        channels: [{ channel: 'ESPN', country: 'United States' }],
      },
      { country: 'Other', channels: [{ channel: 'DAZN' }] },
    ])
    expect(groupBroadcasts([])).toEqual([])
  })
})

describe('near-live refresh', () => {
  it('asks again in 90 s while something is live, else not at all', () => {
    expect(refreshDelay({ live: true, pending: false }, 0)).toBe(
      LIVE_REFRESH_MS,
    )
    expect(refreshDelay({ live: false, pending: false }, 0)).toBeNull()
  })

  it('retries a pending answer after a few seconds, a few times', () => {
    expect(refreshDelay({ live: false, pending: true }, 0)).toBe(
      PENDING_RETRY_MS,
    )
    expect(
      refreshDelay({ live: false, pending: true }, PENDING_MAX_TRIES - 1),
    ).toBe(PENDING_RETRY_MS)
    expect(
      refreshDelay({ live: false, pending: true }, PENDING_MAX_TRIES),
    ).toBeNull()
    expect(refreshDelay({ live: true, pending: true }, PENDING_MAX_TRIES)).toBe(
      LIVE_REFRESH_MS,
    )
  })

  it('reads live and pending off Favorites and the Schedule', () => {
    const favorite = (over: Partial<SportFavorite>): SportFavorite => ({
      entity: {
        kind: 'team',
        id: '133604',
        name: 'Arsenal',
        sport: 'Soccer',
        following: true,
      },
      live: [],
      pending: false,
      ...over,
    })
    expect(
      favoritesState({ items: [favorite({})], unavailable: false }),
    ).toEqual({ live: false, pending: false })
    expect(
      favoritesState({
        items: [favorite({ pending: true }), favorite({ live: [event()] })],
        unavailable: false,
      }),
    ).toEqual({ live: true, pending: true })
    expect(
      scheduleState({
        date: '2026-10-24',
        groups: [
          {
            league: 'Premier League',
            sport: 'Soccer',
            events: [event({ status: 'live' })],
          },
        ],
        pending: false,
        unavailable: false,
      }),
    ).toEqual({ live: true, pending: false })
  })
})

describe('countries', () => {
  it('reads the region from a language tag', () => {
    expect(regionOf('en-GB')).toBe('GB')
    expect(regionOf('pt_BR')).toBe('BR')
    expect(regionOf('zh-Hant-TW')).toBe('TW')
    expect(regionOf('pt')).toBeNull()
    expect(regionOf('es-419')).toBeNull()
    expect(regionOf(undefined)).toBeNull()
  })

  it('names countries and lists them A to Z', () => {
    expect(countryName('PT')).toBe('Portugal')
    expect(isCountryCode('US')).toBe(true)
    expect(isCountryCode('EU')).toBe(false)
    const list = countries()
    expect(list.length).toBeGreaterThan(200)
    expect(new Set(list.map((c) => c.code)).size).toBe(list.length)
    expect(list.map((c) => c.name)).toEqual(
      [...list.map((c) => c.name)].sort((a, b) => a.localeCompare(b)),
    )
  })
})
