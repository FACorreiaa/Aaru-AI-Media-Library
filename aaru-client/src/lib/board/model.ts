import type { components } from '../api/schema'
import { kindOf, statusLabel } from '../library/model'

// BOARD-002: how the friends-only Board reads on the web. Pure display rules; every rule about
// who sees what is the server's.

export type BoardPost = components['schemas']['BoardPost']
export type BoardComment = components['schemas']['BoardComment']
type SpoilerStamp = components['schemas']['SpoilerStamp']
type MediaType = components['schemas']['MediaType']

export type BoardSort = 'recent' | 'top'

/** Posts per Recent page: the server's default page size. */
export const BOARD_PAGE_SIZE = 20

/** Whether "Show older" is offered: a full Recent page may have more behind it; Top never pages. */
export function hasOlder(sort: BoardSort, page: BoardPost[]): boolean {
  return sort === 'recent' && page.length >= BOARD_PAGE_SIZE
}

/** A 1-10 rating as five symbols: whole stars, a half where odd. */
export function starsLabel(rating: number): string {
  const r = Math.max(0, Math.min(10, Math.round(rating)))
  const full = Math.floor(r / 2)
  const half = r % 2 === 1 ? 1 : 0
  return '★'.repeat(full) + '½'.repeat(half) + '☆'.repeat(5 - full - half)
}

/** A 1-10 rating for a screen reader: `9` → "4½ of 5 stars". */
export function ratingWords(rating: number): string {
  const r = Math.max(0, Math.min(10, Math.round(rating)))
  const whole = Math.floor(r / 2)
  const half = r % 2 === 1 ? '½' : ''
  return `${whole > 0 || !half ? whole : ''}${half} of 5 stars`
}

export function spoilerLabel(stamp: SpoilerStamp | undefined): string | null {
  if (!stamp) return null
  if (stamp.ending) return 'Spoilers for the ending'
  if (stamp.season != null && stamp.episode != null) {
    return `Spoilers up to S${stamp.season} · E${stamp.episode}`
  }
  return null
}

/** What posting a review does to the library, in words. Null without a rating: it changes nothing. */
export function reviewEffect(
  hit: { title: string; type: MediaType; libraryItemId?: string },
  rating?: number,
): string | null {
  if (rating == null) return null
  const stars = starsLabel(rating)
  const done = statusLabel('finished', kindOf(hit.type, false))
  if (hit.libraryItemId)
    return `Updates your rating to ${stars}. Its status stays.`
  return `Adds ${hit.title} to ${done}, ${stars}`
}

export type Thread = { comment: BoardComment; replies: BoardComment[] }

export function threadComments(items: BoardComment[]): Thread[] {
  const byId = new Map(items.map((c) => [c.id, c]))
  // A reply to a reply goes to its root; a missing or cyclic parent makes it top-level.
  const rootOf = (c: BoardComment): BoardComment | null => {
    const seen = new Set([c.id])
    let cur = c
    while (cur.replyTo) {
      const parent = byId.get(cur.replyTo)
      if (!parent || seen.has(parent.id)) return cur === c ? null : cur
      seen.add(parent.id)
      cur = parent
    }
    return cur === c ? null : cur
  }
  const threads = new Map<string, Thread>()
  const order: Thread[] = []
  const roots = items.map((c) => ({ c, root: rootOf(c) }))
  for (const { c, root } of roots) {
    if (root) continue
    const t = { comment: c, replies: [] }
    threads.set(c.id, t)
    order.push(t)
  }
  for (const { c, root } of roots) {
    if (root) threads.get(root.id)?.replies.push(c)
  }
  return order
}

export function mergeComments(
  current: BoardComment[],
  page: BoardComment[],
): BoardComment[] {
  const seen = new Set(current.map((c) => c.id))
  const out = [...current]
  for (const c of page) {
    if (seen.has(c.id)) continue
    seen.add(c.id)
    out.push(c)
  }
  return out
}

/** A page can be empty and still have a next one (a cursor skipping hidden rows). */
export function shouldLoadMore(page: {
  items: unknown[]
  next?: string | null
}): boolean {
  return Boolean(page.next)
}

export type UpvoteState = { upvotes: number; upvotedByMe: boolean }

export function toggleUpvote(s: UpvoteState): UpvoteState {
  return s.upvotedByMe
    ? { upvotes: Math.max(0, s.upvotes - 1), upvotedByMe: false }
    : { upvotes: s.upvotes + 1, upvotedByMe: true }
}

export function boardEmpty(
  posts: BoardPost[],
  friendCount: number,
): 'no-friends' | 'quiet' | null {
  if (posts.length > 0) return null
  return friendCount === 0 ? 'no-friends' : 'quiet'
}

/**
 * Who upvoted, in words: "Ana", "Ana and Ben", "Ana, Ben and 10 others". `names` are in the
 * order given (the caller puts "You" first when the viewer upvoted). Null with nobody.
 */
export function upvotersLine(names: string[]): string | null {
  if (names.length === 0) return null
  if (names.length === 1) return names[0]
  if (names.length === 2) return `${names[0]} and ${names[1]}`
  const rest = names.length - 2
  return `${names[0]}, ${names[1]} and ${rest} ${rest === 1 ? 'other' : 'others'}`
}

/**
 * The loaded comments after one is deleted, as the server would page them: a top-level comment
 * with live replies stays as a blank "Comment deleted" row so its replies keep their place;
 * anything else leaves. A parent left with no live replies goes with it.
 */
export function dropComment(items: BoardComment[], id: string): BoardComment[] {
  const target = items.find((c) => c.id === id)
  if (!target) return items
  const live = (parent: string, without: string) =>
    items.some((c) => c.replyTo === parent && c.id !== without && !c.deleted)
  return items.flatMap((c) => {
    if (c.id === id) {
      return live(id, id)
        ? [{ ...c, deleted: true, body: '', author: undefined, mine: false }]
        : []
    }
    // The reply was the last live one under a deleted parent: the parent goes too.
    if (c.id === target.replyTo && c.deleted && !live(c.id, id)) return []
    return [c]
  })
}

/** What a reply answers: the top-level comment it hangs from, whom it names, and its first words. */
export type ReplyTarget = {
  /** Sent as `replyTo`: always a top-level comment, since threads are one level deep. */
  id: string
  /** Who "Replying to" names: the author of the comment Reply was pressed on. */
  author?: BoardComment['author']
  /** `@ben ` when answering a reply, so Ben is tagged; empty for a top-level comment. */
  prefill: string
}

/**
 * Reply on `comment`. A top-level comment is answered as itself. A reply is answered under its
 * top-level comment (its `replyTo`, loaded or not), tagging the reply's author.
 */
export function replyTarget(comment: BoardComment): ReplyTarget {
  if (!comment.replyTo) {
    return { id: comment.id, author: comment.author, prefill: '' }
  }
  return {
    id: comment.replyTo,
    author: comment.author,
    prefill: comment.author ? `@${comment.author.handle} ` : '',
  }
}

/**
 * The box's text when the reply target changes from one prefill to another: an untouched box (or
 * one holding only the old prefill) takes the new one; typed words keep, with the new tag in
 * front unless they already start with it.
 */
export function prefillReply(text: string, from: string, to: string): string {
  if (text.trim() === '' || text === from) return to
  const rest = from && text.startsWith(from) ? text.slice(from.length) : text
  return rest.startsWith(to) ? rest : to + rest
}
