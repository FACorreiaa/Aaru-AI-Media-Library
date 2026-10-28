import { describe, expect, it } from 'vitest'
import {
  DEFAULT_DESCRIPTION,
  addNext,
  shareDate,
  shareDescription,
  shareImage,
  shareName,
  shouldAutoAdd,
} from './model'
import type { SharePreview } from './model'

const DEFAULT_IMAGE = 'https://aaruapp.com/og.jpg'

function title(extra: Partial<NonNullable<SharePreview['title']>> = {}) {
  return {
    kind: 'title',
    unavailable: false,
    title: {
      id: '00000000-0000-0000-0000-000000000001',
      type: 'movie',
      title: 'Arrival',
      year: 2016,
      isAnime: false,
      ids: { tmdb: '329865' },
      ...extra,
    },
  } satisfies SharePreview
}

function match(
  extra: Partial<NonNullable<SharePreview['sportEvent']>> = {},
): SharePreview {
  return {
    kind: 'sport_event',
    unavailable: false,
    sportEvent: {
      id: '2070001',
      sport: 'Soccer',
      name: 'Arsenal vs Chelsea',
      league: 'Premier League',
      home: { name: 'Arsenal', score: 2 },
      away: { name: 'Chelsea', score: 1 },
      day: '2026-11-14',
      status: 'finished',
      isFavorite: false,
      ...extra,
    },
  }
}

const concert: SharePreview = {
  kind: 'concert',
  unavailable: false,
  concert: {
    id: 'G5vYZ9',
    name: 'Radiohead',
    artists: ['Radiohead'],
    localDate: '2026-11-14',
    venue: 'O2 Arena',
    city: 'London',
    url: 'https://www.ticketmaster.co.uk/event/G5vYZ9',
  },
}

const gone: SharePreview = { kind: 'concert', unavailable: true }

describe('shareDescription', () => {
  it('reads a title as kind, year and byline', () => {
    expect(shareDescription(title())).toBe('Film · 2016')
    expect(
      shareDescription(
        title({
          type: 'book',
          title: 'Dune',
          year: 1965,
          byline: 'Frank Herbert',
        }),
      ),
    ).toBe('Book · 1965 · Frank Herbert')
  })

  it('puts the score up front', () => {
    expect(shareDescription(match())).toBe(
      'Arsenal 2–1 Chelsea · Premier League',
    )
    expect(shareDescription(match({ status: 'live' }))).toBe(
      'Arsenal 2–1 Chelsea · Live · Premier League',
    )
  })

  it('reads a match to come with its day', () => {
    expect(
      shareDescription(
        match({
          status: 'scheduled',
          home: { name: 'Arsenal' },
          away: { name: 'Chelsea' },
        }),
      ),
    ).toBe('Arsenal v Chelsea · Premier League · Sat 14 Nov 2026')
  })

  it('reads a card by its name', () => {
    expect(
      shareDescription(
        match({
          name: 'UFC 320',
          league: undefined,
          home: undefined,
          away: undefined,
          status: 'scheduled',
        }),
      ),
    ).toBe('UFC 320 · Sat 14 Nov 2026')
  })

  it('reads a concert as day and place', () => {
    expect(shareDescription(concert)).toBe(
      'Sat 14 Nov 2026 · O2 Arena · London',
    )
  })

  it('falls back when the provider could not give it', () => {
    expect(shareDescription(gone)).toBe(DEFAULT_DESCRIPTION)
  })
})

describe('shareImage', () => {
  it('uses the catalog image', () => {
    expect(
      shareImage(title({ posterUrl: 'https://image.tmdb.org/t/p/w500/x.jpg' })),
    ).toBe('https://image.tmdb.org/t/p/w500/x.jpg')
    expect(
      shareImage(
        match({
          home: {
            name: 'Arsenal',
            score: 2,
            badgeUrl: 'https://r2.thesportsdb.com/a.png',
          },
        }),
      ),
    ).toBe('https://r2.thesportsdb.com/a.png')
  })

  it('takes only absolute https images', () => {
    for (const imageUrl of ['http://x', '/x.jpg'])
      expect(
        shareImage({
          ...concert,
          concert: { ...concert.concert!, imageUrl },
        }),
      ).toBe(DEFAULT_IMAGE)
    expect(shareImage(gone)).toBe(DEFAULT_IMAGE)
  })
})

describe('shareName', () => {
  it('names what is shared, or nothing', () => {
    expect(shareName(match())).toBe('Arsenal v Chelsea')
    expect(shareName(title())).toBe('Arrival')
    expect(shareName(concert)).toBe('Radiohead')
    expect(shareName(gone)).toBeNull()
  })
})

describe('shareDate', () => {
  it('writes a day in full, and leaves anything else alone', () => {
    expect(shareDate('2026-11-14')).toBe('Sat 14 Nov 2026')
    expect(shareDate('soon')).toBe('soon')
  })
})

describe('shouldAutoAdd', () => {
  it('adds a shared title once, on return from sign-in', () => {
    expect(shouldAutoAdd({ add: true, signedIn: true, preview: title() })).toBe(
      true,
    )
  })

  it('never adds twice, signed out, unasked, or for a match', () => {
    const owned = {
      ...title(),
      libraryItemId: '00000000-0000-0000-0000-000000000009',
    }
    expect(shouldAutoAdd({ add: true, signedIn: true, preview: owned })).toBe(
      false,
    )
    expect(
      shouldAutoAdd({ add: true, signedIn: false, preview: title() }),
    ).toBe(false)
    expect(
      shouldAutoAdd({ add: false, signedIn: true, preview: title() }),
    ).toBe(false)
    expect(shouldAutoAdd({ add: true, signedIn: true, preview: match() })).toBe(
      false,
    )
  })
})

describe('addNext', () => {
  it('returns to the link with add', () => {
    expect(addNext('abc')).toBe('/s/abc?add=1')
  })
})
