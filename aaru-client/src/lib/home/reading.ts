import type { LibraryEntry } from '../library/model'
import { nowItem, recentKey } from '../library/now'
import type { NowItem } from '../library/now'
import { isReading } from './model'

// Home's Reading row (owner, 2026-10-25), apart from `model.ts` so the Field and Discover only
// load the Now cards when there is something to read.

/** Most cards the row shows before "All N". */
export const READING_LIMIT = 12

/** Books and manga in progress, last touched first. */
export function reading(entries: LibraryEntry[]): NowItem[] {
  return entries
    .filter(isReading)
    .sort((a, b) => recentKey(b).localeCompare(recentKey(a)))
    .map(nowItem)
}

/** What one step on a Reading card did, for its Undo toast. */
export type ReadingStep =
  { page: number } | { chapter: number } | { finished: true }

export function stepMessage(name: string, step: ReadingStep): string {
  if ('page' in step) return `On page ${step.page} of ${name}`
  if ('chapter' in step) return `Read to chapter ${step.chapter} of ${name}`
  return `Marked ${name} read`
}
