import { describe, expect, it } from 'vitest'
import type { CatalogHit, LibraryStatus } from '../library/model'
import {
  continueLabel,
  cyclePick,
  favoriteCandidates,
  livePicks,
  markSaved,
  mergeFavorites,
  nextStatus,
  pickHeading,
  pickItems,
  pickLabel,
  pickOptions,
  relatedGroups,
  relatedTitleIds,
  sampleAlertTitle,
  setPick,
  stepAfter,
  stepBefore,
  stepKind,
  steps,
  toggleStar,
  unsent,
} from './model'
import { welcomeNext } from './next'
import type { OnboardingPick, OnboardingRelatedItem } from './model'

const hit = (
  tmdb: string,
  type: CatalogHit['type'] = 'show',
  isAnime = false,
): CatalogHit => ({
  type,
  title: `Title ${tmdb}`,
  year: 2020,
  isAnime,
  ids: { tmdb },
})

const saved = (
  h: CatalogHit,
  status: LibraryStatus,
  titleId = `t-${h.ids.tmdb}`,
): OnboardingPick => ({
  ...setPick([], h, status)[0],
  saved: { titleId, libraryItemId: `li-${titleId}` },
})

describe('nextStatus', () => {
  it('cycles shows and anime through watching', () => {
    const seen: Array<LibraryStatus | null> = []
    let status: LibraryStatus | null = null
    for (let i = 0; i < 4; i++) {
      status = nextStatus(status, 'show')
      seen.push(status)
    }
    expect(seen).toEqual(['finished', 'in_progress', 'wishlist', null])
    expect(nextStatus('in_progress', 'anime')).toBe('wishlist')
  })

  it('cycles books and manga through reading', () => {
    expect(nextStatus(null, 'book')).toBe('finished')
    expect(nextStatus('finished', 'book')).toBe('in_progress')
    expect(nextStatus('in_progress', 'manga')).toBe('wishlist')
    expect(nextStatus('wishlist', 'manga')).toBeNull()
  })

  it('skips in progress for films and albums', () => {
    expect(nextStatus(null, 'film')).toBe('finished')
    expect(nextStatus('finished', 'film')).toBe('wishlist')
    expect(nextStatus('wishlist', 'film')).toBeNull()
    expect(nextStatus('finished', 'album')).toBe('wishlist')
    expect(nextStatus('wishlist', 'album')).toBeNull()
  })

  it('starts over from a status the cycle does not hold', () => {
    expect(nextStatus('on_hold', 'show')).toBe('finished')
    expect(nextStatus('in_progress', 'film')).toBe('finished')
  })
})

describe('steps', () => {
  const none = { picks: [], hasRelated: false, pushSupported: true }

  it('puts one picker per kind in library order, whatever the order chosen', () => {
    expect(steps({ ...none, kinds: ['album', 'film', 'anime'] })).toEqual([
      'kinds',
      'pick:film',
      'pick:anime',
      'pick:album',
    ])
  })

  it('is the kinds screen alone with nothing chosen', () => {
    expect(steps({ ...none, kinds: [] })).toEqual(['kinds'])
  })

  it('shows favorites only after a finished pick', () => {
    expect(
      steps({
        ...none,
        kinds: ['book'],
        picks: [{ kind: 'book', status: 'wishlist' }],
      }),
    ).not.toContain('favorites')
    expect(
      steps({
        ...none,
        kinds: ['book'],
        picks: [{ kind: 'book', status: 'finished' }],
      }),
    ).toEqual(['kinds', 'pick:book', 'favorites'])
  })

  it('shows related only when there is some', () => {
    expect(steps({ ...none, kinds: ['film'], hasRelated: true })).toEqual([
      'kinds',
      'pick:film',
      'related',
    ])
  })

  it('asks about alerts only for a show or anime in progress, where push works', () => {
    const watching = [
      { kind: 'anime' as const, status: 'in_progress' as const },
    ]
    expect(steps({ ...none, kinds: ['anime'], picks: watching })).toEqual([
      'kinds',
      'pick:anime',
      'notifications',
    ])
    expect(
      steps({
        ...none,
        kinds: ['anime'],
        picks: watching,
        pushSupported: false,
      }),
    ).not.toContain('notifications')
    expect(
      steps({
        ...none,
        kinds: ['book'],
        picks: [{ kind: 'book', status: 'in_progress' }],
      }),
    ).not.toContain('notifications')
    expect(
      steps({
        ...none,
        kinds: ['show'],
        picks: [{ kind: 'show', status: 'finished' }],
      }),
    ).not.toContain('notifications')
  })

  it('orders every screen', () => {
    expect(
      steps({
        kinds: ['show', 'film'],
        picks: [
          { kind: 'film', status: 'finished' },
          { kind: 'show', status: 'in_progress' },
        ],
        hasRelated: true,
        pushSupported: true,
      }),
    ).toEqual([
      'kinds',
      'pick:film',
      'pick:show',
      'favorites',
      'related',
      'notifications',
    ])
  })

  it('walks forward and back', () => {
    const list = steps({ ...none, kinds: ['film', 'book'] })
    expect(stepAfter(list, 'kinds')).toBe('pick:film')
    expect(stepAfter(list, 'pick:book')).toBeNull()
    expect(stepAfter(list, 'related')).toBeNull()
    expect(stepBefore(list, 'pick:film')).toBe('kinds')
    expect(stepBefore(list, 'kinds')).toBeNull()
    expect(stepKind('pick:book')).toBe('book')
    expect(stepKind('favorites')).toBeNull()
  })
})

describe('copy', () => {
  it('names each kind', () => {
    expect(pickHeading('film')).toBe("Pick films you've watched")
    expect(pickHeading('show')).toBe('Pick shows you watch')
    expect(pickHeading('anime')).toBe('Pick anime you watch')
    expect(pickHeading('manga')).toBe("Pick manga you've read")
    expect(pickHeading('book')).toBe("Pick books you've read")
    expect(pickHeading('album')).toBe("Pick albums you've heard")
  })

  it('reads Skip with nothing picked and Continue with a count', () => {
    expect(continueLabel('film', 0)).toBe('Skip films')
    expect(continueLabel('album', 0)).toBe('Skip albums')
    expect(continueLabel('anime', 0)).toBe('Skip anime')
    expect(continueLabel('show', 3)).toBe('Continue (3)')
  })

  it('labels the chip and the menu per kind, without Dropped', () => {
    expect(pickLabel('finished', 'book')).toBe('Read')
    expect(pickLabel('in_progress', 'show')).toBe('Watching')
    expect(pickLabel('wishlist', 'album')).toBe('Plan to listen')
    expect(pickOptions('film').map((o) => o.status)).toEqual([
      'wishlist',
      'in_progress',
      'on_hold',
      'finished',
    ])
  })
})

describe('picks', () => {
  it('cycles a poster on each tap and keeps tap order', () => {
    let picks = cyclePick([], hit('1', 'movie'))
    picks = cyclePick(picks, hit('2'))
    expect(picks.map((p) => [p.key, p.kind, p.status])).toEqual([
      ['tmdb:1', 'film', 'finished'],
      ['tmdb:2', 'show', 'finished'],
    ])
    picks = cyclePick(picks, hit('1', 'movie'))
    expect(picks[0].status).toBe('wishlist')
    picks = cyclePick(picks, hit('1', 'movie'))
    expect(picks.map((p) => p.key)).toEqual(['tmdb:2'])
  })

  it('sets a status from the menu and removes', () => {
    let picks = setPick([], hit('1'), 'on_hold')
    expect(picks[0].status).toBe('on_hold')
    picks = setPick(picks, hit('1'), null)
    expect(picks).toEqual([])
  })

  it('never changes a saved pick', () => {
    const picks = [saved(hit('1'), 'finished')]
    expect(cyclePick(picks, hit('1'))).toEqual(picks)
    expect(setPick(picks, hit('1'), null)).toEqual(picks)
  })

  it('tells anime from shows', () => {
    expect(cyclePick([], hit('9', 'show', true))[0].kind).toBe('anime')
  })

  it('sends only the unsaved picks of one kind, with their refs', () => {
    const picks = [
      saved(hit('1'), 'finished'),
      ...cyclePick([], hit('2')),
      ...cyclePick([], hit('3', 'movie')),
    ]
    const batch = unsent(picks, 'show')
    expect(batch.map((p) => p.key)).toEqual(['tmdb:2'])
    expect(pickItems(batch)).toEqual([
      {
        mediaRef: {
          type: 'show',
          ids: { tmdb: '2' },
          title: 'Title 2',
          year: 2020,
        },
        status: 'finished',
      },
    ])
  })

  it('marks what the server saved, by index, and leaves a miss unsaved', () => {
    const picks = [...cyclePick([], hit('1')), ...cyclePick([], hit('2'))]
    const after = markSaved(picks, picks, {
      items: [{ index: 1, titleId: 'b', libraryItemId: 'lb' }],
    })
    expect(after[0].saved).toBeUndefined()
    expect(after[1].saved).toEqual({ titleId: 'b', libraryItemId: 'lb' })
  })

  it('counts saved picks and those of kinds still chosen', () => {
    const picks = [
      saved(hit('1'), 'finished'),
      ...cyclePick([], hit('2', 'movie')),
    ]
    expect(livePicks(picks, []).map((p) => p.key)).toEqual(['tmdb:1'])
    expect(livePicks(picks, ['film'])).toHaveLength(2)
  })
})

describe('related', () => {
  it('asks for saved titles once each, at most 30', () => {
    const many = Array.from({ length: 35 }, (_, i) =>
      saved(hit(String(i)), 'finished'),
    )
    const ids = relatedTitleIds([...cyclePick([], hit('x')), ...many, many[0]])
    expect(ids).toHaveLength(30)
    expect(ids[0]).toBe('t-0')
  })

  it('groups by the pick they come from, in order', () => {
    const item = (from: string, id: string): OnboardingRelatedItem => ({
      hit: hit(id),
      relation: 'sequel',
      fromTitleId: from,
      fromTitle: `From ${from}`,
    })
    const groups = relatedGroups([
      item('a', '1'),
      item('b', '2'),
      item('a', '3'),
    ])
    expect(
      groups.map((g) => [g.fromTitle, g.items.map((h) => h.ids.tmdb)]),
    ).toEqual([
      ['From a', ['1', '3']],
      ['From b', ['2']],
    ])
  })
})

describe('favorites', () => {
  const a = saved(hit('1', 'movie'), 'finished')
  const b = saved(hit('2', 'movie'), 'finished')
  const c = saved(hit('3'), 'finished')

  it('offers saved finished picks by kind in library order', () => {
    const picks = [
      c,
      a,
      saved(hit('4', 'movie'), 'wishlist'),
      ...cyclePick([], hit('5', 'movie')),
    ]
    expect(
      favoriteCandidates(picks).map((g) => [g.kind, g.picks.map((p) => p.key)]),
    ).toEqual([
      ['film', ['tmdb:1']],
      ['show', ['tmdb:3']],
    ])
  })

  it('stars in tap order, unstars, and holds ten a kind', () => {
    let stars = toggleStar([], b)
    stars = toggleStar(stars, a)
    expect(stars.map((s) => s.key)).toEqual(['tmdb:2', 'tmdb:1'])
    stars = toggleStar(stars, b)
    expect(stars.map((s) => s.key)).toEqual(['tmdb:1'])
    expect(toggleStar([a], b, 1)).toEqual([a])
    expect(toggleStar([a], c, 1)).toEqual([a, c])
  })

  it('keeps existing favorites first, then new stars, once each, ten at most', () => {
    const existing = [
      {
        id: 't-2',
        type: 'movie' as const,
        title: 'x',
        isAnime: false,
        ids: {},
      },
    ]
    expect(mergeFavorites(existing, [a, b])).toEqual([
      { titleId: 't-2', type: 'movie' },
      { titleId: 't-1', type: 'movie' },
    ])
    expect(mergeFavorites(existing, [a], 1)).toEqual([
      { titleId: 't-2', type: 'movie' },
    ])
  })
})

describe('the rest', () => {
  it('takes the first show or anime in progress for the sample alert', () => {
    const picks = [
      saved(hit('1', 'book'), 'in_progress'),
      saved(hit('2'), 'finished'),
      saved(hit('3', 'show', true), 'in_progress'),
    ]
    expect(sampleAlertTitle(picks)?.key).toBe('tmdb:3')
    expect(sampleAlertTitle([])).toBeNull()
  })

  it('never sends the flow back into itself', () => {
    expect(welcomeNext('/app/library')).toBe('/app/library')
    expect(welcomeNext('/app/welcome')).toBe('/app')
    expect(welcomeNext('/app/welcome?next=%2Fapp')).toBe('/app')
  })
})
