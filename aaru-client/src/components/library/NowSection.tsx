import { Link } from '@tanstack/solid-router'
import { For, Show, createMemo } from 'solid-js'
import { nowSections } from '../../lib/library/now'
import type { LibraryEntry, MediaKind } from '../../lib/library/model'
import { NowCard } from './NowCard'
import { createNowWrites } from './nowWrites'
import { Alert, AlertDescription, buttonVariants } from '~/components/ui'
import { cn } from '~/lib/utils'

// APP-017 · "Now" at the top of Library: what the user is in the middle of, as big cards with a
// progress bar and the one next step — tick the next episode, move a book's page, finish. Each
// write is optimistic about nothing: the card waits for the server's entry and the shelf below
// takes the same entry, so both always agree.
//
// Each group shows its newest NOW_CAP cards; "Show all N" opens the group's own page (APP-018),
// with every title, a grid or a list, and the full facts. Anime the user never touched in Aaru
// (the backlog) are left out here and wait on that page.

/** Fills two rows of the wide grid (three columns) and three of the medium one. */
export const NOW_CAP = 6

export function NowSection(props: {
  entries: LibraryEntry[]
  kind: MediaKind | null
  onEntry: (entry: LibraryEntry) => void
}) {
  const sections = createMemo(() => nowSections(props.entries, props.kind))
  const writes = createNowWrites((entry) => props.onEntry(entry))

  return (
    <Show when={sections().length > 0}>
      <div class="mt-6 flex flex-col gap-8" aria-label="Now">
        <Show when={writes.problem()}>
          {(message) => (
            <Alert variant="destructive">
              <AlertDescription>{message()}</AlertDescription>
            </Alert>
          )}
        </Show>
        <For each={sections()}>
          {(section) => (
            <section aria-labelledby={`now-${section.group}`}>
              <div class="flex items-baseline justify-between gap-4">
                <h2
                  id={`now-${section.group}`}
                  class="font-display text-2xl font-medium tracking-tight"
                >
                  {section.title}
                </h2>
                <Show
                  when={section.items.length > NOW_CAP}
                  fallback={
                    <span class="text-sm text-muted">
                      {section.items.length}
                    </span>
                  }
                >
                  <Link
                    to="/app/library/now/$group"
                    params={{ group: section.group }}
                    search={{ kind: props.kind ?? undefined }}
                    class={cn(
                      buttonVariants({ variant: 'link', size: 'bare' }),
                      'text-sm font-medium',
                    )}
                  >
                    Show all {section.items.length}
                  </Link>
                </Show>
              </div>
              <Show when={section.items.length > 0}>
                <ul class="-mx-5 mt-3 flex snap-x snap-mandatory scroll-px-5 gap-4 overflow-x-auto px-5 pb-2 md:mx-0 md:grid md:grid-cols-2 md:overflow-visible md:px-0 xl:grid-cols-3">
                  <For each={section.items.slice(0, NOW_CAP)}>
                    {(item) => (
                      <NowCard
                        item={item}
                        pending={writes.isPending(item)}
                        {...writes.actions(item)}
                      />
                    )}
                  </For>
                </ul>
              </Show>
              <Show when={section.backlogCount > 0}>
                <Link
                  to="/app/library/now/$group"
                  params={{ group: section.group }}
                  search={{ kind: props.kind ?? undefined }}
                  hash="backlog"
                  class="mt-3 inline-block text-sm text-muted hover:text-ink hover:underline"
                >
                  {section.backlogCount === 1
                    ? '1 anime in your backlog →'
                    : `${section.backlogCount} anime in your backlog →`}
                </Link>
              </Show>
            </section>
          )}
        </For>
      </div>
    </Show>
  )
}
