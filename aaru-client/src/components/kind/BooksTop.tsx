import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal, onMount } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { CaptureCard } from '../CaptureCard'
import { CaptureComposer } from '../CaptureComposer'
import { waitingCaptures } from '../../lib/capture/model'
import { listImports } from '../../lib/imports/server'
import type { ImportJob } from '../../lib/imports/server'
import { shelf, statusLabel } from '../../lib/library/model'
import type { LibraryEntry } from '../../lib/library/model'
import { getStats } from '../../lib/recap/server'

const count = new Intl.NumberFormat('en')

/** The import box: the composer for books only, and the way to a Goodreads export. */
function ImportBox(props: { class?: string }) {
  return (
    <div class={props.class}>
      <CaptureComposer kind="book" class="" />
      <Link
        to="/app/settings/import"
        class="mt-3 inline-block text-sm font-medium text-accent hover:underline"
      >
        Have a Goodreads export? Import it
      </Link>
    </div>
  )
}

/**
 * The top of Books (BOOK-002): this year's reading, captures waiting, and, while the shelf is
 * empty, the import box itself. Once there are books the box moves behind `BooksImportButton`.
 */
export function BooksTop(props: {
  entries: LibraryEntry[]
  shelfEmpty: boolean
}) {
  const [read, setRead] = createSignal(0)
  const [waiting, setWaiting] = createSignal<ImportJob[]>([])
  const reading = () => shelf(props.entries, 'book', 'in_progress').length
  const planned = () => shelf(props.entries, 'book', 'wishlist').length

  // The year and its time zone are the viewer's, which only the browser knows. Both are extras:
  // the page stands without them.
  onMount(() => {
    getStats({
      data: {
        year: new Date().getFullYear(),
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
      },
    }).then(
      (stats) => setRead(stats.totals.booksFinished),
      () => {},
    )
    listImports().then(
      (jobs) => setWaiting(waitingCaptures(jobs)),
      () => {},
    )
  })

  return (
    <>
      <Show when={read() + reading() + planned() > 0}>
        <Link
          to="/app/insights"
          class="mt-8 flex max-w-xl gap-8 rounded-card border border-line bg-surface p-5 hover:bg-surface/80"
        >
          <Figure value={read()} label="Read this year" />
          <Figure
            value={reading()}
            label={statusLabel('in_progress', 'book')}
          />
          <Figure value={planned()} label={statusLabel('wishlist', 'book')} />
        </Link>
      </Show>
      <Show when={waiting().length > 0}>
        <div class="mt-8 grid max-w-xl gap-3">
          <For each={waiting()}>
            {(job) => <CaptureCard job={job} from="books" />}
          </For>
        </div>
      </Show>
      <Show when={props.shelfEmpty}>
        <ImportBox class="mt-8 max-w-2xl" />
      </Show>
    </>
  )
}

function Figure(props: { value: number; label: string }) {
  return (
    <span class="block">
      <span class="block font-display text-2xl font-medium tabular-nums">
        {count.format(props.value)}
      </span>
      <span class="block text-sm text-muted">{props.label}</span>
    </span>
  )
}

/** The page's button once the shelf has books: the import box in a dialog. */
export function BooksImportButton() {
  const [open, setOpen] = createSignal(false)
  return (
    <>
      <Button variant="outline" onClick={() => setOpen(true)}>
        Import books
      </Button>
      <Dialog open={open()} onOpenChange={setOpen}>
        <DialogPortal>
          <DialogContent class="block w-[min(36rem,calc(100vw-2rem))] gap-0 p-5 sm:max-w-none">
            <DialogTitle class="mb-4 text-xl">Import books</DialogTitle>
            <ImportBox />
          </DialogContent>
        </DialogPortal>
      </Dialog>
    </>
  )
}
