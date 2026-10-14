import { describe, expect, it } from 'vitest'
import { idKeys, isOnShelf, kindOf, shelf, toRow, upsert } from './model'
import type { CatalogHit, LibraryEntry } from './model'

function entry(
  id: string,
  overrides: Partial<LibraryEntry> = {},
): LibraryEntry {
  return {
    id,
    status: 'wishlist',
    isOwned: false,
    addedAt: '2026-10-01T00:00:00Z',
    updatedAt: '2026-10-01T00:00:00Z',
    title: {
      id: `t-${id}`,
      type: 'show',
      title: `Title ${id}`,
      isAnime: false,
      ids: { tmdb: id },
    },
    ...overrides,
  }
}

describe('library model', () => {
  it('puts anime on its own shelf, whatever its type', () => {
    expect(kindOf('show', true)).toBe('anime')
    expect(kindOf('movie', true)).toBe('anime')
    expect(kindOf('movie', false)).toBe('film')
    expect(kindOf('book', false)).toBe('book')
  })

  it('shows progress as episodes or pages', () => {
    expect(
      toRow(entry('a', { progress: { watchedCount: 3, airedCount: 10 } }))
        .detail,
    ).toBe('3 of 10 episodes')
    expect(toRow(entry('b', { bookProgress: { page: 42 } })).detail).toBe(
      'Page 42',
    )
    expect(toRow(entry('c')).detail).toBeUndefined()
  })

  it('filters by kind and status, newest change first', () => {
    const entries = [
      entry('old', { updatedAt: '2026-10-01T00:00:00Z' }),
      entry('new', { updatedAt: '2026-10-05T00:00:00Z', status: 'finished' }),
    ]
    expect(shelf(entries, null, null).map((r) => r.id)).toEqual(['new', 'old'])
    expect(shelf(entries, null, 'finished').map((r) => r.id)).toEqual(['new'])
    expect(shelf(entries, 'book', null)).toEqual([])
  })

  it('knows a search hit is on the shelf by any shared provider id', () => {
    const hit: CatalogHit = {
      type: 'show',
      title: 'Same',
      isAnime: false,
      ids: { imdb: 'tt1', tmdb: 'a' },
    }
    expect(isOnShelf(hit, [entry('a')])).toBe(true)
    expect(isOnShelf({ ...hit, ids: { tmdb: 'zzz' } }, [entry('a')])).toBe(
      false,
    )
    expect(idKeys({ tmdb: '1', imdb: '' })).toEqual(['tmdb:1'])
  })

  it('an add replaces by id instead of duplicating', () => {
    const entries = [entry('a'), entry('b')]
    const updated = upsert(entries, entry('a', { status: 'finished' }))
    expect(updated).toHaveLength(2)
    expect(updated[0]).toMatchObject({ id: 'a', status: 'finished' })
  })
})
