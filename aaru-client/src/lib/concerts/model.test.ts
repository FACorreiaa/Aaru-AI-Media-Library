import { describe, expect, it } from 'vitest'
import {
  artistsEmptyLine,
  dateBlock,
  detailLine,
  distanceLabel,
  isRetiredConcertsView,
  parseView,
  pendingLine,
  placeLabel,
  placeLine,
  placeQuery,
  roundCoordinate,
  roundPosition,
  searchEmptyLine,
  searchHeading,
} from './model'
import type { Concert } from './model'

const concert = (over: Partial<Concert> = {}): Concert => ({
  id: 'e1',
  name: 'Big Thief',
  artists: ['Big Thief'],
  localDate: '2026-10-24',
  url: 'https://www.ticketmaster.com/event/e1',
  ...over,
})

describe('discover view', () => {
  it('reads the three views and nothing else', () => {
    expect(parseView('today')).toBe('today')
    expect(parseView('on-air')).toBe('on-air')
    expect(parseView('seasons')).toBe('seasons')
    expect(parseView('Seasons')).toBeUndefined()
    expect(parseView(3)).toBeUndefined()
    expect(parseView(undefined)).toBeUndefined()
  })

  it('no longer has a Concerts view (NAV-001)', () => {
    expect(parseView('concerts')).toBeUndefined()
  })

  it('sends only the old Concerts view on to Music', () => {
    expect(isRetiredConcertsView('concerts')).toBe(true)
    expect(isRetiredConcertsView('Concerts')).toBe(false)
    expect(isRetiredConcertsView('seasons')).toBe(false)
    expect(isRetiredConcertsView(undefined)).toBe(false)
  })
})

describe('date block', () => {
  it('reads the venue date as given', () => {
    expect(dateBlock('2026-10-24', '2026-10-21')).toEqual({
      day: '24',
      month: 'Oct',
      weekday: 'Sat',
      label: 'Saturday 24 October 2026',
    })
    expect(dateBlock('2026-11-01')?.day).toBe('1')
  })

  it('names the year only when it is not this one', () => {
    expect(dateBlock('2027-01-03', '2026-10-21')?.month).toBe('Jan 2027')
    expect(dateBlock('2027-01-03', '2027-01-01')?.month).toBe('Jan')
  })

  it('gets weekdays right across a DST change and a leap day', () => {
    expect(dateBlock('2026-03-29')?.weekday).toBe('Sun')
    expect(dateBlock('2028-02-29')?.weekday).toBe('Tue')
  })

  it('has no block for a date that is not one', () => {
    expect(dateBlock('2026-02-30')).toBeNull()
    expect(dateBlock('24/10/2026')).toBeNull()
    expect(dateBlock('')).toBeNull()
  })
})

describe('row lines', () => {
  it('joins venue and city', () => {
    expect(placeLine(concert({ venue: 'Coliseu', city: 'Porto' }))).toBe(
      'Coliseu · Porto',
    )
    expect(placeLine(concert({ city: 'Porto' }))).toBe('Porto')
    expect(placeLine(concert({ venue: '  ' }))).toBeNull()
  })

  it('joins distance and time, leaving out what is missing', () => {
    expect(detailLine(concert({ distanceKm: 3.4, localTime: '21:00' }))).toBe(
      '3.4 km · 21:00',
    )
    expect(detailLine(concert({ localTime: '20:30:00' }))).toBe('20:30')
    expect(detailLine(concert({ distanceKm: 42.6 }))).toBe('43 km')
    expect(detailLine(concert())).toBeNull()
  })

  it('reads distances plainly', () => {
    expect(distanceLabel(0.04)).toBe('0.1 km')
    expect(distanceLabel(3)).toBe('3 km')
    expect(distanceLabel(9.96)).toBe('10 km')
    expect(distanceLabel(12.4)).toBe('12 km')
  })
})

describe('position', () => {
  it('rounds to two decimals before it is sent', () => {
    expect(roundCoordinate(38.736946)).toBe(38.74)
    expect(roundCoordinate(-9.142685)).toBe(-9.14)
    expect(roundPosition({ latitude: 41.14961, longitude: -8.61099 })).toEqual({
      latitude: 41.15,
      longitude: -8.61,
    })
  })
})

describe('places', () => {
  it('names a city with its region and country, without repeats', () => {
    expect(
      placeLabel({
        name: 'Porto',
        region: 'Porto District',
        country: 'Portugal',
        latitude: 41.15,
        longitude: -8.61,
      }),
    ).toBe('Porto, Porto District, Portugal')
    expect(
      placeLabel({
        name: 'Berlin',
        region: 'Berlin',
        country: 'Germany',
        latitude: 52.52,
        longitude: 13.41,
      }),
    ).toBe('Berlin, Germany')
  })

  it('sends a search only from two characters', () => {
    expect(placeQuery(' p ')).toBeNull()
    expect(placeQuery('  po ')).toBe('po')
    expect(placeQuery('x'.repeat(101))).toBeNull()
  })
})

describe('your artists', () => {
  const found = { items: [], matched: 0, pending: 0, unavailable: false }

  it('says artists are being checked', () => {
    expect(pendingLine(0)).toBeNull()
    expect(pendingLine(1)).toBe('Checking 1 artist — back within the hour.')
    expect(artistsEmptyLine({ ...found, pending: 4 })).toBe(
      'Checking 4 artists — back within the hour.',
    )
  })

  it('points to albums when there are no artists, else says none tour', () => {
    expect(artistsEmptyLine(found)).toMatch(/Albums you add/)
    expect(artistsEmptyLine({ ...found, matched: 3 })).toBe(
      'None of your artists are touring soon.',
    )
    expect(
      artistsEmptyLine({ ...found, matched: 1, items: [concert()] }),
    ).toBeNull()
  })
})

describe('search by artist', () => {
  it('heads the section with the artist and where it looks', () => {
    expect(searchHeading('Radiohead', 'near', 'Lisbon')).toBe(
      'Radiohead near Lisbon',
    )
    expect(searchHeading('Radiohead', 'near', null)).toBe('Radiohead near you')
    expect(searchHeading('Radiohead', 'anywhere', 'Lisbon')).toBe(
      'Radiohead anywhere',
    )
  })

  it('says what was empty: the radius near, every date anywhere', () => {
    expect(searchEmptyLine('Radiohead', 'near', 50)).toBe(
      'No Radiohead concerts within 50 km.',
    )
    expect(searchEmptyLine('Radiohead', 'anywhere', undefined)).toBe(
      'No upcoming Radiohead concerts listed.',
    )
  })
})
