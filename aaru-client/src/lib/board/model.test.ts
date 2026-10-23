import { describe, expect, it } from 'vitest'
import {
  BOARD_PAGE_SIZE,
  boardEmpty,
  dropComment,
  hasOlder,
  mergeComments,
  prefillReply,
  ratingWords,
  replyTarget,
  reviewEffect,
  shouldLoadMore,
  spoilerLabel,
  starsLabel,
  threadComments,
  toggleUpvote,
  upvotersLine,
} from './model'
import type { BoardComment, BoardPost } from './model'

const comment = (
  id: string,
  replyTo?: string,
  over: Partial<BoardComment> = {},
): BoardComment => ({
  id,
  postId: 'p1',
  body: id,
  mentions: [],
  mentionsAgent: false,
  deleted: false,
  createdAt: '2026-10-23T10:00:00Z',
  fromAgent: false,
  replyTo,
  ...over,
})

describe('board model', () => {
  it('renders ratings as five symbols with a half', () => {
    expect(starsLabel(9)).toBe('★★★★½')
    expect(starsLabel(10)).toBe('★★★★★')
    expect(starsLabel(1)).toBe('½☆☆☆☆')
    expect(starsLabel(4)).toBe('★★☆☆☆')
  })

  it('labels spoiler stamps', () => {
    expect(spoilerLabel({ season: 2, episode: 10, ending: false })).toBe(
      'Spoilers up to S2 · E10',
    )
    expect(spoilerLabel({ ending: true })).toBe('Spoilers for the ending')
    expect(spoilerLabel(undefined)).toBeNull()
  })

  it('says what a review does to the library', () => {
    expect(reviewEffect({ title: 'Arrival', type: 'movie' }, 8)).toBe(
      'Adds Arrival to Watched, ★★★★☆',
    )
    expect(reviewEffect({ title: 'Dune', type: 'book' }, 8)).toBe(
      'Adds Dune to Read, ★★★★☆',
    )
    expect(reviewEffect({ title: 'Severance', type: 'show' }, 9)).toBe(
      "Adds Severance to Watched, or Watching if it's still airing, ★★★★½",
    )
    expect(
      reviewEffect({ title: 'Arrival', type: 'movie', libraryItemId: 'x' }, 9),
    ).toBe('Updates your rating to ★★★★½. Its status stays.')
    expect(reviewEffect({ title: 'Arrival', type: 'movie' })).toBeNull()
  })

  it('threads replies under their parent', () => {
    const [c1, r1, c2, r2] = [
      comment('C1'),
      comment('R1', 'C1'),
      comment('C2'),
      comment('R2', 'C1'),
    ]
    expect(threadComments([c1, r1, c2, r2])).toEqual([
      { comment: c1, replies: [r1, r2] },
      { comment: c2, replies: [] },
    ])
    const orphan = comment('O', 'gone')
    expect(threadComments([orphan])).toEqual([{ comment: orphan, replies: [] }])
  })

  it('flattens a reply to a reply onto its root', () => {
    const [c1, r1, r1a] = [
      comment('C1'),
      comment('R1', 'C1'),
      comment('R1a', 'R1'),
    ]
    expect(threadComments([c1, r1, r1a])).toEqual([
      { comment: c1, replies: [r1, r1a] },
    ])
  })

  it('keeps replies under a deleted parent', () => {
    const c1 = comment('C1', undefined, { deleted: true, body: '' })
    const [r1, r2] = [comment('R1', 'C1'), comment('R2', 'C1')]
    expect(threadComments([c1, r1, r2])).toEqual([
      { comment: c1, replies: [r1, r2] },
    ])
  })

  it('merges comment pages without duplicates', () => {
    const a = comment('a')
    const b = comment('b')
    const c = comment('c')
    expect(mergeComments([a, b], [b, c]).map((x) => x.id)).toEqual([
      'a',
      'b',
      'c',
    ])
  })

  it('loads more whenever next is set', () => {
    expect(shouldLoadMore({ items: [], next: 'x' })).toBe(true)
    expect(shouldLoadMore({ items: [1], next: null })).toBe(false)
    expect(shouldLoadMore({ items: [1] })).toBe(false)
  })

  it('toggles an upvote', () => {
    const on = toggleUpvote({ upvotes: 3, upvotedByMe: false })
    expect(on).toEqual({ upvotes: 4, upvotedByMe: true })
    expect(toggleUpvote(on)).toEqual({ upvotes: 3, upvotedByMe: false })
  })

  it('clamps upvotes at zero', () => {
    expect(toggleUpvote({ upvotes: 0, upvotedByMe: true })).toEqual({
      upvotes: 0,
      upvotedByMe: false,
    })
  })

  it('tells an empty board from a quiet one', () => {
    const post = { id: 'p' } as BoardPost
    expect(boardEmpty([], 0)).toBe('no-friends')
    expect(boardEmpty([], 2)).toBe('quiet')
    expect(boardEmpty([post], 2)).toBeNull()
  })

  it('offers older posts only after a full Recent page', () => {
    const page = (n: number) =>
      Array.from({ length: n }, (_, i) => ({ id: `p${i}` }) as BoardPost)
    expect(hasOlder('recent', page(BOARD_PAGE_SIZE))).toBe(true)
    expect(hasOlder('recent', page(BOARD_PAGE_SIZE - 1))).toBe(false)
    expect(hasOlder('top', page(BOARD_PAGE_SIZE))).toBe(false)
  })

  it('says a rating in words', () => {
    expect(ratingWords(9)).toBe('4½ of 5 stars')
    expect(ratingWords(2)).toBe('1 of 5 stars')
    expect(ratingWords(1)).toBe('½ of 5 stars')
  })

  it('names the first two upvoters, then counts the rest', () => {
    expect(upvotersLine([])).toBeNull()
    expect(upvotersLine(['Ana'])).toBe('Ana')
    expect(upvotersLine(['Ana', 'Ben'])).toBe('Ana and Ben')
    expect(upvotersLine(['Ana', 'Ben', 'Cy'])).toBe('Ana, Ben and 1 other')
    expect(
      upvotersLine(['Ana', 'Ben', ...Array.from({ length: 10 }, () => 'x')]),
    ).toBe('Ana, Ben and 10 others')
  })

  it('keeps a deleted comment with live replies as a blank row', () => {
    const items = [
      comment('a', undefined, {
        author: { userId: 'u', handle: 'ana' },
        mine: true,
      }),
      comment('b', 'a'),
    ]
    const left = dropComment(items, 'a')
    expect(left.map((c) => c.id)).toEqual(['a', 'b'])
    expect(left[0]).toMatchObject({ deleted: true, body: '', mine: false })
    expect(left[0].author).toBeUndefined()
    expect(threadComments(left)[0].replies.map((c) => c.id)).toEqual(['b'])
  })

  it('drops a deleted comment without replies, and an emptied deleted parent', () => {
    expect(dropComment([comment('a')], 'a')).toEqual([])
    const items = [
      comment('a', undefined, { deleted: true }),
      comment('b', 'a'),
    ]
    expect(dropComment(items, 'b')).toEqual([])
    const kept = [comment('a'), comment('b', 'a'), comment('c', 'a')]
    expect(dropComment(kept, 'b').map((c) => c.id)).toEqual(['a', 'c'])
  })

  it('replies to a reply under its top-level comment, tagging its author', () => {
    const ana = { userId: 'a', handle: 'ana' }
    const ben = { userId: 'b', handle: 'ben' }
    expect(replyTarget(comment('a', undefined, { author: ana }))).toEqual({
      id: 'a',
      author: ana,
      prefill: '',
    })
    expect(replyTarget(comment('b', 'a', { author: ben }))).toEqual({
      id: 'a',
      author: ben,
      prefill: '@ben ',
    })
  })

  it('answers an orphan reply under its own replyTo, never its own id', () => {
    // Its parent is not loaded, so threading shows it top-level; the server still wants the root.
    const orphan = comment('b', 'gone', {
      author: { userId: 'b', handle: 'ben' },
    })
    expect(threadComments([orphan])[0].comment.id).toBe('b')
    expect(replyTarget(orphan).id).toBe('gone')
  })

  it('swaps a prefill without losing typed words', () => {
    expect(prefillReply('', '', '@ben ')).toBe('@ben ')
    expect(prefillReply('@ben ', '@ben ', '@cy ')).toBe('@cy ')
    expect(prefillReply('@ben great', '@ben ', '@cy ')).toBe('@cy great')
    expect(prefillReply('so true', '', '@ben ')).toBe('@ben so true')
    expect(prefillReply('@ben ', '@ben ', '')).toBe('')
    expect(prefillReply('@ben hi', '@ben ', '')).toBe('hi')
  })
})
