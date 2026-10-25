import { describe, expect, it } from 'vitest'
import type { LibraryEntry } from '../library/model'
import { SHELF_LIMIT, kindShelves, kindSources } from './page'

function entry(
  id: string,
  type: LibraryEntry['title']['type'],
  status: LibraryEntry['status'],
  updatedAt = '2026-10-01T00:00:00Z',
): LibraryEntry {
  return {
    id,
    status,
    isOwned: false,
    inBacklog: false,
    addedAt: '2026-10-01T00:00:00Z',
    updatedAt,
    title: {
      id: `t-${id}`,
      type,
      title: `Title ${id}`,
      isAnime: false,
      ids: { tmdb: id },
    },
  }
}

describe('kind shelves', () => {
  const entries = [
    entry('b1', 'book', 'in_progress', '2026-10-02T00:00:00Z'),
    entry('b2', 'book', 'in_progress', '2026-10-05T00:00:00Z'),
    entry('b3', 'book', 'wishlist'),
    entry('b4', 'book', 'finished'),
    entry('m1', 'manga', 'in_progress'),
    entry('a1', 'album', 'wishlist'),
    entry('s1', 'show', 'in_progress'),
  ]

  it('leads with In progress, then Planned, labelled for the kind', () => {
    const shelves = kindShelves(entries, 'book')
    expect(shelves.map((s) => s.label)).toEqual(['Reading', 'Plan to read'])
    expect(shelves[0].rows.map((r) => r.id)).toEqual(['b2', 'b1'])
    expect(shelves[1].rows.map((r) => r.id)).toEqual(['b3'])
  })

  it('keeps each kind to its own titles', () => {
    expect(kindShelves(entries, 'manga')[0].rows.map((r) => r.id)).toEqual([
      'm1',
    ])
    const albums = kindShelves(entries, 'album')
    expect(albums.map((s) => s.label)).toEqual(['Listening', 'Plan to listen'])
    expect(albums[0].rows).toEqual([])
    expect(albums[1].rows.map((r) => r.id)).toEqual(['a1'])
  })

  it('shows a short row but counts them all', () => {
    const many = Array.from({ length: SHELF_LIMIT + 3 }, (_, i) =>
      entry(`b${i}`, 'book', 'wishlist'),
    )
    const planned = kindShelves(many, 'book')[1]
    expect(planned.rows).toHaveLength(SHELF_LIMIT)
    expect(planned.total).toBe(SHELF_LIMIT + 3)
  })

  it('is two empty shelves for an empty library', () => {
    expect(
      kindShelves([], 'manga').map((s) => [s.label, s.rows.length]),
    ).toEqual([
      ['Reading', 0],
      ['Plan to read', 0],
    ])
  })
})

describe('kind sources', () => {
  it('credits only the providers of the page’s rows', () => {
    expect(kindSources('book').map((s) => s.name)).toEqual(['Open Library'])
    expect(kindSources('manga').map((s) => s.name)).toEqual(['AniList'])
    expect(kindSources('album').map((s) => s.name)).toEqual([
      'ListenBrainz',
      'MusicBrainz',
      'Cover Art Archive',
    ])
    for (const kind of ['book', 'manga', 'album'] as const)
      for (const source of kindSources(kind))
        expect(source.href).toMatch(/^https:\/\//)
  })
})
