import { Link } from '@tanstack/solid-router'
import { For, Show, createMemo } from 'solid-js'
import { Row } from './HomeRows'
import { NowCard } from './library/NowCard'
import { createNowWrites } from './library/nowWrites'
import { READING_LIMIT, reading } from '../lib/home/reading'
import type { LibraryEntry } from '../lib/library/model'
import { Alert } from '~/components/ui'

/**
 * The Field's Reading row (owner, 2026-10-25): books and manga in progress, last touched first,
 * on the Library's Now cards, so a page, a chapter or "Mark read" is one step there too, with
 * Undo. Loaded only when the library has something to read.
 */
export default function ReadingRow(props: {
  entries: LibraryEntry[]
  onEntry: (entry: LibraryEntry) => void
  onUndone: () => void
}) {
  const items = createMemo(() => reading(props.entries))
  const writes = createNowWrites(props.onEntry, props.onUndone)
  return (
    <>
      <Row
        title="Reading"
        action={
          <Show when={items().length > READING_LIMIT}>
            <Link
              to="/app/library/now/$group"
              params={{ group: 'reading' }}
              class="text-sm font-medium text-accent hover:underline"
            >
              All {items().length}
            </Link>
          </Show>
        }
      >
        <For each={items().slice(0, READING_LIMIT)}>
          {(item) => (
            <NowCard
              item={item}
              inRow
              pending={writes.isPending(item)}
              {...writes.actions(item)}
            />
          )}
        </For>
      </Row>
      <Show when={writes.problem()}>
        {(message) => (
          <Alert variant="destructive" class="mt-3">
            {message()}
          </Alert>
        )}
      </Show>
    </>
  )
}
