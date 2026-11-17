import { describe, expect, it } from 'vitest'
import { asksWhereToWatch, watchGroups } from './watch'
import type { TitleWatch } from './watch'

describe('where to watch (CAT-014)', () => {
  it('shows only the groups that have a service, streaming first', () => {
    const places: TitleWatch = {
      region: 'PT',
      streaming: [{ name: 'Netflix' }],
      rent: [],
      buy: [{ name: 'Apple TV' }, { name: 'Rakuten TV' }],
    }
    const groups = watchGroups(places)
    expect(groups.map((g) => g.kind)).toEqual(['stream', 'buy'])
    expect(groups[0].label).toBe('Stream')
    expect(groups[1].services.map((s) => s.name)).toEqual([
      'Apple TV',
      'Rakuten TV',
    ])
  })

  it('has no groups when there is nothing to show', () => {
    expect(watchGroups(null)).toEqual([])
    expect(watchGroups(undefined)).toEqual([])
    expect(
      watchGroups({ region: 'JP', streaming: [], rent: [], buy: [] }),
    ).toEqual([])
  })

  it('asks only for watched kinds, and only with a region', () => {
    expect(asksWhereToWatch('film', 'PT')).toBe(true)
    expect(asksWhereToWatch('show', 'US')).toBe(true)
    expect(asksWhereToWatch('anime', 'US')).toBe(true)
    expect(asksWhereToWatch('book', 'PT')).toBe(false)
    expect(asksWhereToWatch('manga', 'PT')).toBe(false)
    expect(asksWhereToWatch('album', 'PT')).toBe(false)
    expect(asksWhereToWatch('film', undefined)).toBe(false)
  })
})
