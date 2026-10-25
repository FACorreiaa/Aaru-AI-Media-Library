import { Link } from '@tanstack/solid-router'
import { For, Index, Show, createMemo, createSignal, onMount } from 'solid-js'
import type { JSX } from 'solid-js'
import { Button } from '~/components/ui'
import { DiscoverRows } from '../DiscoverRows'
import { Row } from '../HomeRows'
import { Poster } from '../Poster'
import { useAppShell, useSearchHost } from '../shell/context'
import { localDayKey } from '../../lib/calendar/model'
import { rowsOfKinds } from '../../lib/discover/kind'
import type { DiscoverRow } from '../../lib/home/model'
import { kindShelves, kindSources } from '../../lib/kind/page'
import type { PageKind } from '../../lib/kind/page'
import { markOnShelf } from '../../lib/home/model'
import { upsert } from '../../lib/library/model'
import type { LibraryEntry, LibraryRow } from '../../lib/library/model'

/** What the empty shelf says, per kind. */
const EMPTY: Record<PageKind, string> = {
  book: 'Nothing on your reading shelf yet. Add a book from the rows below, or search for one.',
  manga:
    'Nothing on your manga shelf yet. Add a series from the rows below, or search for one.',
  album:
    'No albums on your shelf yet. Add one from the rows below, or search for one.',
}

const SEARCH_LABEL: Record<PageKind, string> = {
  book: 'Search books',
  manga: 'Search manga',
  album: 'Search albums',
}

/**
 * NAV-001: the Books, Manga and Music pages. The user's shelf for one kind leads (In progress,
 * then Planned, each a short row into Library filtered to it), then that kind's public rows
 * from Discover, then any sections the page adds (Music: Concerts and Listens). The rows come
 * from the same cache as Home and Discover; the shelf from the same library as Library.
 */
export function KindPage(props: {
  kind: PageKind
  title: string
  blurb: string
  entries: LibraryEntry[]
  /** Every Discover row; the page keeps its kind's. */
  rows: DiscoverRow[]
  /** Why the public rows could not be loaded, if they could not. */
  rowsProblem: string | null
  children?: JSX.Element
}) {
  const shell = useAppShell()
  const [entries, setEntries] = createSignal<LibraryEntry[]>(props.entries)
  const [rows, setRows] = createSignal<DiscoverRow[]>(
    rowsOfKinds(props.rows, [props.kind]),
  )
  const [problem, setProblem] = createSignal<string | null>(null)
  const [today, setToday] = createSignal<string | null>(null)
  // The release badges count days from the viewer's today, which only the browser knows.
  onMount(() => setToday(localDayKey(new Date())))

  function added(entry: LibraryEntry) {
    setEntries((list) => upsert(list, entry))
    setRows((current) => markOnShelf(current, entry))
  }
  // An add from Search lands on this page's shelf at once.
  useSearchHost({ entries, onAdded: added })

  const shelves = createMemo(() => kindShelves(entries(), props.kind))
  const shelfEmpty = () => shelves().every((s) => s.rows.length === 0)
  const shown = () => rows().filter((row) => row.items.length > 0)
  const sources = () => kindSources(props.kind)

  return (
    <div class="flex-1">
      <div class="w-full min-w-0 px-4 pt-6 pb-16 md:px-8 lg:pt-8 2xl:px-12">
        <div class="mt-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="font-display text-4xl font-medium tracking-tight">
              {props.title}
            </h1>
            <p class="mt-2 text-muted">{props.blurb}</p>
          </div>
          <Button
            variant="outline"
            onClick={() => shell.openSearch(props.kind)}
          >
            {SEARCH_LABEL[props.kind]}
          </Button>
        </div>

        <Show when={problem()}>
          {(message) => (
            <p role="alert" class="mt-4 text-sm text-danger">
              {message()}
            </p>
          )}
        </Show>

        <Show
          when={!shelfEmpty()}
          fallback={
            <p class="mt-8 max-w-prose text-muted">{EMPTY[props.kind]}</p>
          }
        >
          <For each={shelves()}>
            {(s) => (
              <Show when={s.rows.length > 0}>
                <Row
                  title={s.label}
                  action={
                    <Link
                      to="/app/library"
                      search={{ kind: props.kind, status: s.status }}
                      class="text-sm font-medium text-accent hover:underline"
                      aria-label={`See all ${s.total} in ${s.label}`}
                    >
                      See all
                    </Link>
                  }
                >
                  <Index each={s.rows}>
                    {(row) => <ShelfCard row={row()} />}
                  </Index>
                </Row>
              </Show>
            )}
          </For>
        </Show>

        <Show
          when={shown().length > 0}
          fallback={
            <Show when={props.rowsProblem}>
              <p class="mt-10 text-sm text-muted">
                The public rows could not be loaded right now. Search still
                works.
              </p>
            </Show>
          }
        >
          <DiscoverRows
            rows={shown()}
            onRowsChange={setRows}
            today={today()}
            onAdded={(entry) => setEntries((list) => upsert(list, entry))}
            onProblem={setProblem}
          />
        </Show>

        {props.children}

        <footer class="mt-16 border-t border-line pt-6 text-sm text-muted">
          Rows from{' '}
          <For each={sources()}>
            {(source, i) => (
              <>
                {i() > 0 && (i() === sources().length - 1 ? ' and ' : ', ')}
                <a
                  href={source.href}
                  rel="noopener"
                  class="font-medium text-accent hover:underline"
                >
                  {source.name}
                </a>
              </>
            )}
          </For>
          .{' '}
          <Link
            to="/about"
            hash="credits"
            class="font-medium text-accent hover:underline"
          >
            Credits
          </Link>
        </footer>
      </div>
    </div>
  )
}

/** One title on the shelf: its cover, name, and the artist or where the user is. */
function ShelfCard(props: { row: LibraryRow }) {
  const line = () =>
    props.row.kind === 'album' ? props.row.byline : props.row.detail
  return (
    <Link
      to="/app/title/$id"
      params={{ id: props.row.id }}
      class="block w-32 shrink-0 snap-start md:w-36"
    >
      <Poster url={props.row.posterUrl} kind={props.row.kind} />
      <p class="mt-2 line-clamp-2 text-sm font-medium">{props.row.title}</p>
      <Show when={line()}>
        {(text) => <p class="truncate text-xs text-muted">{text()}</p>}
      </Show>
    </Link>
  )
}
