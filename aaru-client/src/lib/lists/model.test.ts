import { describe, expect, it } from 'vitest'
import { isOnList, toListRow } from './model'
import type { ListItem } from './model'
import type { CatalogHit } from '../library/model'

function item(id: string, overrides: Partial<ListItem> = {}): ListItem {
  return {
    title: {
      id: `t-${id}`,
      type: 'show',
      title: `Title ${id}`,
      isAnime: false,
      network: 'Apple TV+',
      ids: { tmdb: id },
    },
    ...overrides,
  }
}

const now = new Date('2026-10-15T12:00:00Z')

describe('list model', () => {
  it('shows show status and the next airing for a title outside the library', () => {
    const row = toListRow(
      item('a', {
        showStatus: 'returning',
        nextAiring: {
          season: 2,
          number: 3,
          airsAt: '2026-10-16T00:00:00Z',
          airTimeKnown: false,
        },
      }),
      now,
    )
    expect(row.libraryItemId).toBeUndefined()
    expect(row.status).toBeUndefined()
    expect(row.showStatus).toBe('Returning')
    expect(row.network).toBe('Apple TV+')
    expect(row.airing).toBe('S2 · E3 · Tomorrow')
  })

  it('names only the episode until the page knows the time', () => {
    const row = toListRow(
      item('a', {
        nextAiring: {
          season: 1,
          number: 1,
          airsAt: '2026-10-16T00:00:00Z',
          airTimeKnown: false,
        },
      }),
      null,
    )
    expect(row.airing).toBe('S1 · E1')
  })

  it('carries the library status and progress, and links by library item', () => {
    const row = toListRow(
      item('b', {
        entry: {
          id: 'li-b',
          status: 'in_progress',
          isOwned: false,
          addedAt: '2026-10-01T00:00:00Z',
          updatedAt: '2026-10-01T00:00:00Z',
          title: item('b').title,
          progress: { watchedCount: 4, airedCount: 8 },
        },
      }),
      now,
    )
    expect(row.libraryItemId).toBe('li-b')
    expect(row.status).toBe('in_progress')
    expect(row.detail).toBe('4 of 8 episodes')
    expect(row.airing).toBeUndefined()
  })

  it('matches a search hit to a member by any provider id', () => {
    const hit = (ids: Record<string, string>) =>
      ({ type: 'show', title: 'X', isAnime: false, ids }) as CatalogHit
    expect(isOnList(hit({ tmdb: 'a' }), [item('a')])).toBe(true)
    expect(isOnList(hit({ tmdb: 'z' }), [item('a')])).toBe(false)
  })
})
