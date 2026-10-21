import { describe, expect, it } from 'vitest'
import { nowItem, nowSections } from './now'
import type { LibraryEntry } from './model'

const entry = (overrides: Partial<LibraryEntry> = {}): LibraryEntry => ({
  id: 'i1',
  title: { id: 't1', type: 'show', title: 'Andor', isAnime: false, ids: {} },
  status: 'in_progress',
  isOwned: false,
  addedAt: '2026-10-01T00:00:00Z',
  updatedAt: '2026-10-10T00:00:00Z',
  ...overrides,
})

describe('library Now', () => {
  it('reads a show as episodes watched of aired, with the next one to tick', () => {
    const item = nowItem(
      entry({
        progress: {
          watchedCount: 4,
          airedCount: 10,
          nextEpisode: { season: 1, number: 5 },
        },
      }),
    )
    expect(item.done).toBe(0.4)
    expect(item.progressLabel).toBe('4 of 10 episodes')
    expect(item.next).toEqual({ season: 1, number: 5, label: 'S1 · E5' })
  })

  it('reads a book by percent, else by page', () => {
    const book = {
      id: 'b',
      type: 'book' as const,
      title: 'Dune',
      isAnime: false,
      ids: {},
    }
    expect(
      nowItem(entry({ title: book, bookProgress: { percent: 35 } })),
    ).toMatchObject({ done: 0.35, progressLabel: '35%' })
    const paged = nowItem(entry({ title: book, bookProgress: { page: 120 } }))
    expect(paged.progressLabel).toBe('Page 120')
    expect(paged.done).toBeUndefined()
    expect(nowItem(entry({ title: book })).progressLabel).toBe('Just started')
  })

  it('groups in-progress items, newest first, and narrows to a kind', () => {
    const book = entry({
      id: 'b',
      title: { id: 'b', type: 'book', title: 'Dune', isAnime: false, ids: {} },
      updatedAt: '2026-10-12T00:00:00Z',
    })
    const film = entry({
      id: 'f',
      title: {
        id: 'f',
        type: 'movie',
        title: 'Arrival',
        isAnime: false,
        ids: {},
      },
      updatedAt: '2026-10-11T00:00:00Z',
    })
    const later = entry({ id: 'w', status: 'wishlist' })
    const sections = nowSections([entry(), book, film, later])
    expect(sections.map((s) => s.group)).toEqual(['watching', 'reading'])
    expect(sections[0].items.map((i) => i.entry.id)).toEqual(['f', 'i1'])
    expect(nowSections([entry(), book], 'book').map((s) => s.group)).toEqual([
      'reading',
    ])
  })
})
