import { describe, expect, it } from 'vitest'
import {
  KINDS,
  coverShape,
  idKeys,
  isOnShelf,
  kindOf,
  mangaProgressLabel,
  shelf,
  statusLabel,
  statusOptions,
  toRow,
  upsert,
} from './model'
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
    expect(kindOf('album', false)).toBe('album')
  })

  it('files albums under Music, with a square cover', () => {
    expect(KINDS.find((k) => k.kind === 'album')).toEqual({
      kind: 'album',
      label: 'Music',
      search: 'album',
    })
    expect(coverShape('album')).toBe('square')
    expect(coverShape('film')).toBe('poster')
    expect(coverShape('book')).toBe('poster')
  })

  it("carries an album's artist on its row", () => {
    const album = entry('m', {
      title: {
        id: 't-m',
        type: 'album',
        title: 'OK Computer',
        byline: 'Radiohead',
        isAnime: false,
        ids: { musicbrainz: 'b1392450-e666-3926-a536-22c65f834433' },
      },
    })
    expect(toRow(album)).toMatchObject({
      kind: 'album',
      byline: 'Radiohead',
      detail: undefined,
    })
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

describe('manga (MNG-001)', () => {
  const manga = (overrides: Partial<LibraryEntry> = {}) =>
    entry('m', {
      title: {
        id: 't-m',
        type: 'manga',
        title: 'Berserk',
        isAnime: false,
        ids: { anilist: '30002' },
        chapterCount: 364,
      },
      ...overrides,
    })

  it('is its own shelf, read like a book, with a poster', () => {
    expect(kindOf('manga', false)).toBe('manga')
    expect(KINDS.map((k) => k.kind)).toContain('manga')
    expect(coverShape('manga')).toBe('poster')
    expect(statusLabel('in_progress', 'manga')).toBe('Reading')
    expect(statusLabel('wishlist', 'manga')).toBe('Plan to read')
  })

  it('names the chapter against the total, and the volume', () => {
    expect(mangaProgressLabel(manga())).toBeUndefined()
    expect(
      mangaProgressLabel(
        manga({ mangaProgress: { chapter: 112, volume: 12 } }),
      ),
    ).toBe('Ch. 112 of 364 · Vol. 12')
    expect(mangaProgressLabel(manga({ mangaProgress: { volume: 3 } }))).toBe(
      'Vol. 3',
    )
    expect(toRow(manga({ mangaProgress: { chapter: 5 } })).detail).toBe(
      'Ch. 5 of 364',
    )
  })
})

describe('status labels', () => {
  const labels = (kind: Parameters<typeof statusOptions>[0]) =>
    statusOptions(kind).map((o) => o.label)

  it('speaks of watching for films, shows and anime', () => {
    for (const kind of ['film', 'show', 'anime'] as const) {
      expect(labels(kind)).toEqual([
        'Plan to watch',
        'Watching',
        'Watched',
        'Dropped',
      ])
    }
    expect(statusLabel('in_progress', 'anime')).toBe('Watching')
  })

  it('speaks of reading for books', () => {
    expect(labels('book')).toEqual([
      'Plan to read',
      'Reading',
      'Read',
      'Dropped',
    ])
    expect(statusLabel('finished', 'book')).toBe('Read')
  })

  it('speaks of listening for albums', () => {
    expect(labels('album')).toEqual([
      'Plan to listen',
      'Listening',
      'Listened',
      'Dropped',
    ])
    expect(statusLabel('in_progress', 'album')).toBe('Listening')
  })

  it('uses neutral words when no kind is chosen', () => {
    expect(labels(null)).toEqual([
      'Planned',
      'In progress',
      'Finished',
      'Dropped',
    ])
    expect(statusLabel('wishlist', null)).toBe('Planned')
  })

  it('keeps the stored values and their order whatever the words', () => {
    for (const kind of ['film', 'book', 'album', null] as const) {
      expect(statusOptions(kind).map((o) => o.status)).toEqual([
        'wishlist',
        'in_progress',
        'finished',
        'dropped',
      ])
    }
  })
})
