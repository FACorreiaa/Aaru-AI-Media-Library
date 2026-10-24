import { describe, expect, it } from 'vitest'
import { hitKey } from '../library/model'
import {
  episodeLine,
  markOnAir,
  showCount,
  streamsLine,
  viewerRegion,
} from './onAir'
import type { OnAirGuide, OnAirShow } from './onAir'

const show = (overrides: Partial<OnAirShow> = {}): OnAirShow => ({
  item: {
    type: 'show',
    title: 'Drama',
    isAnime: false,
    ids: { tmdb: '101' },
  },
  nextEpisode: {
    season: 2,
    number: 5,
    airsAt: '2026-10-22T00:00:00Z',
    airTimeKnown: false,
  },
  ...overrides,
})

describe('viewer region', () => {
  it('reads the region from the language, filling it in when absent', () => {
    expect(viewerRegion('en-US')).toBe('US')
    expect(viewerRegion('pt-PT')).toBe('PT')
    expect(viewerRegion('pt')).toBe('BR')
  })

  it('has none for a missing or broken language', () => {
    expect(viewerRegion(undefined)).toBeUndefined()
    expect(viewerRegion('not a locale!')).toBeUndefined()
  })
})

describe('episode line', () => {
  it('shows the time in the viewer’s zone when it is exact', () => {
    const line = episodeLine(
      {
        season: 2,
        number: 5,
        airsAt: '2026-10-23T01:00:00Z',
        airTimeKnown: true,
      },
      'America/New_York',
      'en-US',
    )
    expect(line).toBe('S2 E5 · Thu 9:00 PM')
  })

  it('shows the listed day alone while only the day is known', () => {
    expect(episodeLine(show().nextEpisode, 'Pacific/Honolulu', 'en-GB')).toBe(
      'S2 E5 · Thu 22 Oct',
    )
  })
})

describe('streams line', () => {
  it('lists the services, joined in words', () => {
    expect(streamsLine(show({ streamsOn: [{ name: 'Hulu' }] }))).toBe(
      'Also on Hulu',
    )
    expect(
      streamsLine(
        show({
          streamsOn: [{ name: 'Hulu' }, { name: 'Max' }, { name: 'Peacock' }],
        }),
      ),
    ).toBe('Also on Hulu, Max and Peacock')
  })

  it('says nothing without services', () => {
    expect(streamsLine(show())).toBeNull()
    expect(streamsLine(show({ streamsOn: [] }))).toBeNull()
  })
})

describe('marking an add', () => {
  it('links every card for the title, wherever it is', () => {
    const guide: OnAirGuide = {
      channels: [
        { name: 'HBO', shows: [show()] },
        {
          name: 'Other',
          shows: [show({ item: { ...show().item, ids: { tmdb: '9' } } })],
        },
      ],
    }
    const marked = markOnAir(guide, hitKey(show().item), 'item-1')
    expect(marked.channels[0].shows[0].item.libraryItemId).toBe('item-1')
    expect(marked.channels[1].shows[0].item.libraryItemId).toBeUndefined()
  })

  it('counts shows in words', () => {
    expect(showCount(1)).toBe('1 show')
    expect(showCount(4)).toBe('4 shows')
  })
})
