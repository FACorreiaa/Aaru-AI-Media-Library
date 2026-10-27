import { describe, expect, it } from 'vitest'
import { reading, stepMessage } from './reading'
import type { LibraryEntry } from '../library/model'

describe('reading row', () => {
  const entry = (
    id: string,
    type: string,
    status: string,
    updatedAt: string,
  ): LibraryEntry =>
    ({
      id,
      status,
      updatedAt,
      title: { type, title: id, isAnime: false },
    }) as unknown as LibraryEntry

  it('holds books and manga in progress, last touched first', () => {
    const rows = reading([
      entry('old book', 'book', 'in_progress', '2026-10-01T10:00:00Z'),
      entry('show', 'show', 'in_progress', '2026-10-25T10:00:00Z'),
      entry('manga', 'manga', 'in_progress', '2026-10-24T10:00:00Z'),
      entry('done', 'book', 'finished', '2026-10-25T10:00:00Z'),
      entry('paused', 'manga', 'on_hold', '2026-10-25T10:00:00Z'),
    ])
    expect(rows.map((item) => item.entry.id)).toEqual(['manga', 'old book'])
  })

  it('names the step for the undo toast', () => {
    expect(stepMessage('Frieren', { chapter: 88 })).toBe(
      'Read to chapter 88 of Frieren',
    )
    expect(stepMessage('Piranesi', { page: 140 })).toBe(
      'On page 140 of Piranesi',
    )
    expect(stepMessage('Piranesi', { finished: true })).toBe(
      'Marked Piranesi read',
    )
  })
})
