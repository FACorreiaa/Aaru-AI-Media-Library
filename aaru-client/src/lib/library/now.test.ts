import { describe, expect, it } from 'vitest'
import { groupItems, nowItem, nowSections, sortNow } from './now'
import { watchingLines } from './watching'
import type { WatchingItem } from './watching'
import type { LibraryEntry } from './model'

const entry = (overrides: Partial<LibraryEntry> = {}): LibraryEntry => ({
  id: 'i1',
  title: { id: 't1', type: 'show', title: 'Andor', isAnime: false, ids: {} },
  status: 'in_progress',
  isOwned: false,
  inBacklog: false,
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
    const counted = nowItem(
      entry({
        title: { ...book, pageCount: 400 },
        bookProgress: { page: 100 },
      }),
    )
    expect(counted).toMatchObject({
      done: 0.25,
      progressLabel: 'Page 100 of 400',
    })
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
    const album = entry({
      id: 'a',
      title: {
        id: 'a',
        type: 'album',
        title: 'Bookends',
        isAnime: false,
        ids: {},
      },
    })
    const sections = nowSections([entry(), book, film, later, album])
    expect(sections.map((s) => s.group)).toEqual([
      'watching',
      'reading',
      'listening',
    ])
    expect(sections[2].items[0].progressLabel).toBe('Listening')
    expect(sections[0].items.map((i) => i.entry.id)).toEqual(['f', 'i1'])
    expect(nowSections([entry(), book], 'book').map((s) => s.group)).toEqual([
      'reading',
    ])
  })
})

describe('Now group pages and the anime backlog (APP-018)', () => {
  const anime = (id: string, inBacklog: boolean, updatedAt: string) =>
    entry({
      id,
      title: { id: `t-${id}`, type: 'show', title: id, isAnime: true, ids: {} },
      inBacklog,
      updatedAt,
    })

  it('counts backlog anime apart from Watching on Library', () => {
    const sections = nowSections([
      anime('Frieren', false, '2026-10-20T00:00:00Z'),
      anime('Gintama', true, '2026-10-24T00:00:00Z'),
      anime('Monster', true, '2026-10-23T00:00:00Z'),
    ])
    expect(sections).toHaveLength(1)
    expect(sections[0].items.map((i) => i.entry.id)).toEqual(['Frieren'])
    expect(sections[0].backlogCount).toBe(2)
  })

  it('keeps a group whose every title is in the backlog, so its page stays reachable', () => {
    const sections = nowSections([
      anime('Gintama', true, '2026-10-24T00:00:00Z'),
    ])
    expect(sections[0]).toMatchObject({ items: [], backlogCount: 1 })
  })

  it('splits a page into active titles and the backlog, narrowed by kind', () => {
    const film = entry({
      id: 'Arrival',
      title: {
        id: 'm',
        type: 'movie',
        title: 'Arrival',
        isAnime: false,
        ids: {},
      },
    })
    const page = groupItems(
      [
        anime('Frieren', false, '2026-10-20T00:00:00Z'),
        anime('Gintama', true, '2026-10-24T00:00:00Z'),
        film,
      ],
      'watching',
    )
    expect(page.active.map((i) => i.entry.id).sort()).toEqual([
      'Arrival',
      'Frieren',
    ])
    expect(page.backlog.map((i) => i.entry.id)).toEqual(['Gintama'])
    expect(
      groupItems(
        [film, anime('Frieren', false, '2026-10-20T00:00:00Z')],
        'watching',
        'film',
      ).active.map((i) => i.entry.id),
    ).toEqual(['Arrival'])
  })

  it('sorts by the last tick made in Aaru, by the next airing, or A–Z', () => {
    const older = nowItem(
      entry({
        id: 'a',
        title: {
          id: 'ta',
          type: 'show',
          title: 'Zeta',
          isAnime: false,
          ids: {},
        },
        updatedAt: '2026-10-24T00:00:00Z',
        lastWatchedAt: '2026-09-01T00:00:00Z',
      }),
    )
    const newer = nowItem(
      entry({
        id: 'b',
        title: {
          id: 'tb',
          type: 'show',
          title: 'Alpha',
          isAnime: false,
          ids: {},
        },
        updatedAt: '2026-10-01T00:00:00Z',
        lastWatchedAt: '2026-10-20T00:00:00Z',
      }),
    )
    const none = nowItem(
      entry({
        id: 'c',
        title: {
          id: 'tc',
          type: 'show',
          title: 'Mid',
          isAnime: false,
          ids: {},
        },
        updatedAt: '2026-10-10T00:00:00Z',
      }),
    )
    const ids = (items: { entry: { id: string } }[]) =>
      items.map((i) => i.entry.id)
    expect(ids(sortNow([older, newer, none], 'recent'))).toEqual([
      'b',
      'c',
      'a',
    ])
    expect(ids(sortNow([older, newer, none], 'title'))).toEqual(['b', 'c', 'a'])
    const airs: Record<string, string> = {
      a: '2026-10-26T00:00:00Z',
      c: '2026-10-25T00:00:00Z',
    }
    expect(
      ids(sortNow([older, newer, none], 'airs', (i) => airs[i.entry.id])),
    ).toEqual(['c', 'a', 'b'])
  })

  it('reads a Watching row: network and status, next episode, what is left, next airing', () => {
    const show = entry({
      title: {
        id: 't1',
        type: 'show',
        title: 'Severance',
        network: 'Apple TV+',
        isAnime: false,
        ids: {},
      },
      progress: {
        watchedCount: 12,
        airedCount: 19,
        nextEpisode: { season: 2, number: 3 },
      },
    })
    const watching: WatchingItem = {
      entry: show,
      showStatus: 'returning',
      nextName: 'Who Is Alive?',
      remainingCount: 7,
      remainingMinutes: 340,
      nextAiring: {
        season: 2,
        number: 10,
        airsAt: '2026-10-26T01:00:00Z',
        airTimeKnown: false,
      },
    }
    expect(
      watchingLines(
        nowItem(show),
        watching,
        new Date('2026-10-25T12:00:00Z'),
        'UTC',
      ),
    ).toEqual([
      'Apple TV+ · Returning',
      'Next S2 · E3 · Who Is Alive?',
      '7 left · 5h 40m',
      'Airs S2 · E10 · Tomorrow',
    ])
  })

  it('says caught up when every aired episode is watched', () => {
    const show = entry({ progress: { watchedCount: 8, airedCount: 8 } })
    expect(
      watchingLines(
        nowItem(show),
        { entry: show, showStatus: 'ended' },
        new Date(),
        'UTC',
      ),
    ).toEqual(['Ended', 'Caught up'])
  })
})
