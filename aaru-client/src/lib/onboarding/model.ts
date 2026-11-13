import type { components } from '../api/schema'
import { hitKey, kindOf, statusLabel, statusOptions } from '../library/model'
import type { CatalogHit, LibraryStatus, MediaKind } from '../library/model'
import { FAVORITE_LIMIT } from '../favorites/model'

// ONB-001 on the web: a new account's first run (DESIGN.md §0a). The pure part, the same cases as
// AaruCore's `Onboarding.swift`: the status a tap moves to, which screens the flow shows, and
// the words on them. The flow component holds the state; this decides it.

export type OnboardingRelatedItem =
  components['schemas']['OnboardingRelatedItem']
export type OnboardingPicked = components['schemas']['OnboardingPicked']
type MediaRef = components['schemas']['MediaRef']
type TitleSummary = components['schemas']['TitleSummary']

/** The six kinds, in Library's order: the order of the picker screens. */
export const ONBOARDING_KINDS = [
  'film',
  'show',
  'anime',
  'manga',
  'book',
  'album',
] as const satisfies readonly MediaKind[]

/** At most this many titles go to `POST /v1/onboarding/related`. */
export const RELATED_LIMIT = 30
/** At most this many picks go in one `POST /v1/onboarding/picks`. */
export const PICKS_LIMIT = 60

export type Step =
  | 'kinds'
  | `pick:${MediaKind}`
  | 'favorites'
  | 'related'
  | 'ai'
  | 'notifications'

/** Kinds you can be in the middle of: a show, an anime, a book, a manga. A film or an album is
 * seen or heard in one go, so its cycle has no Watching / Listening. */
function hasInProgress(kind: MediaKind): boolean {
  return kind !== 'film' && kind !== 'album'
}

/**
 * The status one tap on a poster moves to. The first tap says you have watched, read or heard
 * it; the next ones go through Watching / Reading (where the kind has it) and Plan to…, then off
 * (`null`). A status the cycle does not hold (on hold, dropped, from the menu) starts it over.
 */
export function nextStatus(
  current: LibraryStatus | null,
  kind: MediaKind,
): LibraryStatus | null {
  const cycle: Array<LibraryStatus | null> = hasInProgress(kind)
    ? [null, 'finished', 'in_progress', 'wishlist']
    : [null, 'finished', 'wishlist']
  const at = cycle.indexOf(current)
  if (at === -1) return 'finished'
  return cycle[(at + 1) % cycle.length]
}

/** The statuses the long-press menu offers: every status but Dropped, which nobody picks on
 * day one. Remove is the menu's own last item. */
export function pickOptions(
  kind: MediaKind,
): Array<{ status: LibraryStatus; label: string }> {
  return statusOptions(kind).filter((option) => option.status !== 'dropped')
}

/** What the chip on a picked poster reads: "Watched", "Reading", "Plan to listen". */
export function pickLabel(status: LibraryStatus, kind: MediaKind): string {
  return statusLabel(status, kind)
}

/** The screens, in order. Pickers follow Library's kind order whatever order the kinds were
 * chosen in; favorites need a finished pick, the alerts screen a show or anime in progress and
 * a browser that can take push. */
export function steps(input: {
  kinds: readonly MediaKind[]
  picks: ReadonlyArray<{ kind: MediaKind; status: LibraryStatus }>
  hasRelated: boolean
  pushSupported: boolean
}): Step[] {
  const list: Step[] = ['kinds']
  for (const kind of ONBOARDING_KINDS)
    if (input.kinds.includes(kind)) list.push(`pick:${kind}`)
  if (input.picks.some((pick) => pick.status === 'finished'))
    list.push('favorites')
  if (input.hasRelated) list.push('related')
  // PRV-002: every first run asks about AI sharing, after the picks and before alerts.
  list.push('ai')
  if (
    input.pushSupported &&
    input.picks.some(
      (pick) =>
        (pick.kind === 'show' || pick.kind === 'anime') &&
        pick.status === 'in_progress',
    )
  )
    list.push('notifications')
  return list
}

/** The kind a picker step is for, or null for any other step. */
export function stepKind(step: Step): MediaKind | null {
  return step.startsWith('pick:') ? (step.slice(5) as MediaKind) : null
}

/** The step after `current`, or null at the end (or when `current` left the list: the flow
 * never jumps back to the start on its own). */
export function stepAfter(list: readonly Step[], current: Step): Step | null {
  const at = list.indexOf(current)
  return at === -1 ? null : (list[at + 1] ?? null)
}

/** The step before `current`, or null on the first. */
export function stepBefore(list: readonly Step[], current: Step): Step | null {
  const at = list.indexOf(current)
  return at > 0 ? list[at - 1] : null
}

const HEADINGS: Record<MediaKind, string> = {
  film: "Pick films you've watched",
  show: 'Pick shows you watch',
  anime: 'Pick anime you watch',
  manga: "Pick manga you've read",
  book: "Pick books you've read",
  album: "Pick albums you've heard",
}

const PLURALS: Record<MediaKind, string> = {
  film: 'films',
  show: 'shows',
  anime: 'anime',
  manga: 'manga',
  book: 'books',
  album: 'albums',
}

/** A picker screen's headline. */
export function pickHeading(kind: MediaKind): string {
  return HEADINGS[kind]
}

/** The pill at the bottom of a picker: "Continue (3)", or "Skip shows" with nothing picked.
 * There is no minimum. */
export function continueLabel(kind: MediaKind, count: number): string {
  return count > 0 ? `Continue (${count})` : `Skip ${PLURALS[kind]}`
}

/** One pick on a poster. `saved` once the server has it: it is then in the library and is not
 * sent again. */
export interface OnboardingPick {
  key: string
  hit: CatalogHit
  kind: MediaKind
  status: LibraryStatus
  saved?: { titleId: string; libraryItemId: string }
}

export function hitKind(hit: CatalogHit): MediaKind {
  return kindOf(hit.type, hit.isAnime)
}

/** Sets one poster's status (`null` takes it off). A saved pick is in the library already and
 * stays as it was saved. New picks join the end, so the order is the order they were tapped. */
export function setPick(
  picks: readonly OnboardingPick[],
  hit: CatalogHit,
  status: LibraryStatus | null,
): OnboardingPick[] {
  const key = hitKey(hit)
  const at = picks.findIndex((pick) => pick.key === key)
  if (at !== -1 && picks[at].saved) return [...picks]
  if (status === null) return picks.filter((pick) => pick.key !== key)
  if (at === -1) return [...picks, { key, hit, kind: hitKind(hit), status }]
  return picks.map((pick, index) => (index === at ? { ...pick, status } : pick))
}

/** One tap on a poster: its status moves on through the kind's cycle. */
export function cyclePick(
  picks: readonly OnboardingPick[],
  hit: CatalogHit,
): OnboardingPick[] {
  const key = hitKey(hit)
  const current = picks.find((pick) => pick.key === key)
  if (current?.saved) return [...picks]
  return setPick(picks, hit, nextStatus(current?.status ?? null, hitKind(hit)))
}

/** The picks of one kind not saved yet: what Continue sends. */
export function unsent(
  picks: readonly OnboardingPick[],
  kind: MediaKind,
): OnboardingPick[] {
  return picks.filter((pick) => pick.kind === kind && !pick.saved)
}

/** Picks the flow counts: every saved one, and unsaved ones of a kind still chosen. */
export function livePicks(
  picks: readonly OnboardingPick[],
  kinds: readonly MediaKind[],
): OnboardingPick[] {
  return picks.filter((pick) => pick.saved || kinds.includes(pick.kind))
}

/** The request body for a batch of picks: each by its provider ids, title and year. */
export function pickItems(
  batch: readonly OnboardingPick[],
): Array<{ mediaRef: MediaRef; status: LibraryStatus }> {
  return batch.map((pick) => ({
    mediaRef: {
      type: pick.hit.type,
      ids: pick.hit.ids,
      title: pick.hit.title,
      year: pick.hit.year,
    },
    status: pick.status,
  }))
}

/** Marks the sent picks saved from the server's answer (`index` is the position in the batch).
 * A ref that resolved to no title stays unsaved, so it can be tried again or taken off. */
export function markSaved(
  picks: readonly OnboardingPick[],
  batch: readonly OnboardingPick[],
  answer: { items: OnboardingPicked['items'] },
): OnboardingPick[] {
  const saved = new Map<string, { titleId: string; libraryItemId: string }>()
  for (const item of answer.items) {
    const sent = batch[item.index] as OnboardingPick | undefined
    if (sent)
      saved.set(sent.key, {
        titleId: item.titleId,
        libraryItemId: item.libraryItemId,
      })
  }
  return picks.map((pick) => {
    const ids = saved.get(pick.key)
    return ids ? { ...pick, saved: ids } : pick
  })
}

/** The saved titles to look for relations of, in the order they were picked, at most 30. */
export function relatedTitleIds(picks: readonly OnboardingPick[]): string[] {
  const ids: string[] = []
  for (const pick of picks) {
    if (pick.saved && !ids.includes(pick.saved.titleId))
      ids.push(pick.saved.titleId)
  }
  return ids.slice(0, RELATED_LIMIT)
}

/** The related titles grouped under the pick they come from, in the server's order: "More
 * from Dune". */
export function relatedGroups(
  items: readonly OnboardingRelatedItem[],
): Array<{ fromTitleId: string; fromTitle: string; items: CatalogHit[] }> {
  const groups: Array<{
    fromTitleId: string
    fromTitle: string
    items: CatalogHit[]
  }> = []
  for (const item of items) {
    let group = groups.find((g) => g.fromTitleId === item.fromTitleId)
    if (!group) {
      group = {
        fromTitleId: item.fromTitleId,
        fromTitle: item.fromTitle,
        items: [],
      }
      groups.push(group)
    }
    group.items.push(item.hit)
  }
  return groups
}

/** A related screen's heading for one group. */
export function relatedHeading(fromTitle: string): string {
  return `More from ${fromTitle}`
}

/** The saved finished picks, by kind in Library's order: what the favorites screen offers. */
export function favoriteCandidates(
  picks: readonly OnboardingPick[],
): Array<{ kind: MediaKind; picks: OnboardingPick[] }> {
  return ONBOARDING_KINDS.map((kind) => ({
    kind,
    picks: picks.filter(
      (pick) => pick.kind === kind && pick.saved && pick.status === 'finished',
    ),
  })).filter((group) => group.picks.length > 0)
}

/** Stars or unstars one title. The order is the order of the taps; a kind holds ten, so an
 * eleventh star changes nothing. */
export function toggleStar(
  stars: readonly OnboardingPick[],
  pick: OnboardingPick,
  limit = FAVORITE_LIMIT,
): OnboardingPick[] {
  if (stars.some((star) => star.key === pick.key))
    return stars.filter((star) => star.key !== pick.key)
  const sameKind = stars.filter((star) => star.kind === pick.kind).length
  return sameKind >= limit ? [...stars] : [...stars, pick]
}

/** A kind's favorites after the first run: the ones already there first, then the new stars in
 * tap order, each title once, ten at most. */
export function mergeFavorites(
  existing: readonly TitleSummary[],
  starred: readonly OnboardingPick[],
  limit = FAVORITE_LIMIT,
): MediaRef[] {
  const refs: MediaRef[] = existing.map((title) => ({
    titleId: title.id,
    type: title.type,
  }))
  for (const star of starred) {
    if (!star.saved) continue
    if (refs.some((ref) => ref.titleId === star.saved?.titleId)) continue
    refs.push({ titleId: star.saved.titleId, type: star.hit.type })
  }
  return refs.slice(0, limit)
}

/** The show or anime the sample alert is about: the first one picked as Watching. */
export function sampleAlertTitle(
  picks: readonly OnboardingPick[],
): OnboardingPick | null {
  return (
    picks.find(
      (pick) =>
        (pick.kind === 'show' || pick.kind === 'anime') &&
        pick.status === 'in_progress',
    ) ?? null
  )
}
