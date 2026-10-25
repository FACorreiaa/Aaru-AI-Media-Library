import { Link } from '@tanstack/solid-router'
import { Show, createSignal, createUniqueId } from 'solid-js'
import type { JSX } from 'solid-js'
import { badge, metaLine, shortCode } from '../lib/calendar/model'
import type { CalendarEntry } from '../lib/calendar/model'
import { kindOf } from '../lib/library/model'
import type {
  CatalogHit,
  LibraryEntry,
  LibraryStatus,
} from '../lib/library/model'
import { cardBadge } from '../lib/discover/model'
import {
  nextLine,
  remainingLabel,
  resumeLine,
  runtimeLabel,
  unfinishedLabel,
} from '../lib/home/model'
import type {
  ContinueEntry,
  StartEntry,
  UnfinishedEntry,
} from '../lib/home/model'
import { prefersReducedMotion } from '../lib/reduced-motion'
import { AddControl } from './AddControl'
import { CardMenu } from './CardMenu'
import { Poster } from './Poster'
import { TitleLink } from './TitleLink'
import { Badge, badgeVariants, Button } from '~/components/ui'

// APP-009: Home's rows (DESIGN.md §13). Each row scrolls sideways and snaps; it takes focus so
// the arrow keys scroll it, and on desktop it has its own back / forward buttons. A card that
// holds a library item has its menu (CardMenu): mark it watched, or open it.

/** A horizontal row: a heading, an optional action, and cards that snap as they scroll. */
export function Row(props: {
  title: string
  /** A line under the title, e.g. why a row is a stand-in. */
  note?: string
  action?: JSX.Element
  children: JSX.Element
}) {
  const id = createUniqueId()
  let scroller: HTMLDivElement | undefined
  const scroll = (direction: 1 | -1) =>
    scroller?.scrollBy({
      left: direction * scroller.clientWidth * 0.85,
      behavior: prefersReducedMotion() ? 'auto' : 'smooth',
    })
  return (
    <section class="mt-10" aria-labelledby={id}>
      <div class="flex items-end justify-between gap-4">
        <div>
          <h2 id={id} class="font-display text-2xl font-medium tracking-tight">
            {props.title}
          </h2>
          <Show when={props.note}>
            {(note) => <p class="mt-1 text-xs text-muted">{note()}</p>}
          </Show>
        </div>
        <div class="flex items-center gap-3">
          {props.action}
          <div class="hidden gap-1 md:flex">
            <Button
              variant="quiet"
              size="icon-sm"
              aria-label={`Scroll ${props.title} back`}
              onClick={() => scroll(-1)}
            >
              <Chevron flip />
            </Button>
            <Button
              variant="quiet"
              size="icon-sm"
              aria-label={`Scroll ${props.title} forward`}
              onClick={() => scroll(1)}
            >
              <Chevron />
            </Button>
          </div>
        </div>
      </div>
      <div
        ref={scroller}
        role="region"
        aria-labelledby={id}
        tabindex="0"
        class="-mx-4 mt-4 flex snap-x snap-mandatory scroll-px-4 gap-4 overflow-x-auto px-4 pb-3 focus-visible:outline-2 focus-visible:-outline-offset-2 md:mx-0 md:scroll-px-0 md:px-0"
      >
        {props.children}
      </div>
    </section>
  )
}

function Chevron(props: { flip?: boolean }) {
  return (
    <svg
      viewBox="0 0 20 20"
      class="h-4 w-4"
      classList={{ 'rotate-180': props.flip }}
      aria-hidden="true"
    >
      <path
        d="M7.5 4.5 13 10l-5.5 5.5"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  )
}

/** Wide art: the show's backdrop, then its poster, then a blue-to-amber wash with the title. */
export function Art(props: { sources: (string | undefined)[]; title: string }) {
  const urls = () => props.sources.filter((u): u is string => !!u)
  const [failed, setFailed] = createSignal(0)
  const url = () => urls()[failed()]
  return (
    <Show
      when={url()}
      keyed
      fallback={
        <div class="grid h-full place-items-center bg-surface edge-lit px-4 text-center font-display text-lg leading-tight text-ink/75">
          {props.title}
        </div>
      }
    >
      {(src) => (
        <img
          src={src}
          alt=""
          loading="lazy"
          decoding="async"
          class="h-full w-full object-cover"
          onError={() => setFailed((n) => n + 1)}
        />
      )}
    </Show>
  )
}

/** Text on art: a dark scrim chip, legible on any image in either theme. */
const chip = badgeVariants({ variant: 'scrim' })

/** Continue watching: the next episode of an in-progress show, with a check to mark it. The
 * card hands back its element, so a show that leaves the row can play its exit first. */
export function ContinueCard(props: {
  entry: ContinueEntry
  busy: boolean
  onWatched: (entry: ContinueEntry, card: HTMLElement) => void
  onChanged: (entry?: LibraryEntry) => void
}) {
  const e = () => props.entry
  const runtime = () => runtimeLabel(e().nextRuntimeMinutes)
  let card!: HTMLElement
  return (
    <article ref={card} class="w-[min(78vw,22rem)] shrink-0 snap-start">
      <CardMenu
        id={e().libraryItemId}
        name={e().title.title}
        target={{ type: e().title.type, status: 'in_progress' }}
        onChanged={props.onChanged}
        triggerClass="top-2 left-2"
      >
        <Link
          to="/app/title/$id"
          params={{ id: e().libraryItemId }}
          tabindex="-1"
          aria-hidden="true"
          class="relative block aspect-video overflow-hidden rounded-panel shadow-[0_0_0_1px_var(--line)]"
        >
          <Art
            sources={[e().title.backdropUrl, e().title.posterUrl]}
            title={e().title.title}
          />
          <Show when={e().isFinale}>
            <Badge variant="ink" class="absolute top-2 right-2">
              Finale
            </Badge>
          </Show>
          <div class="absolute inset-x-2 bottom-2 flex items-end justify-between gap-2">
            <Show when={runtime()} fallback={<span />}>
              <span class={chip}>{runtime()}</span>
            </Show>
            <span class={chip}>
              {remainingLabel(e().remainingCount, e().remainingMinutes)}
            </span>
          </div>
        </Link>
        <div class="mt-2 flex items-start gap-3">
          <div class="min-w-0 flex-1">
            <Link
              to="/app/title/$id"
              params={{ id: e().libraryItemId }}
              class="block truncate font-semibold hover:underline"
            >
              {e().title.title}
            </Link>
            <p class="truncate text-sm text-muted">{nextLine(e())}</p>
          </div>
          <Button
            variant="quiet"
            size="bare"
            disabled={props.busy}
            onClick={() => props.onWatched(e(), card)}
            aria-label={`Mark ${e().title.title} ${shortCode(e().next.season, e().next.number)} watched`}
            class="size-9 shrink-0 font-normal text-accent hover:bg-accent hover:text-on-accent"
          >
            <svg viewBox="0 0 20 20" class="h-4 w-4" aria-hidden="true">
              <path
                d="m4.5 10.5 3.5 3.5 7.5-8"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </Button>
        </div>
      </CardMenu>
    </article>
  )
}

/** Start watching: a wishlist film, show or anime and how long it takes. Albums are not in it
 *  (UX-052): in progress they have Listening. */
export function StartCard(props: {
  entry: StartEntry
  onChanged: (entry?: LibraryEntry) => void
}) {
  const e = () => props.entry
  const kind = () => kindOf(e().title.type, e().title.isAnime)
  const detail = () =>
    kind() === 'album'
      ? e().title.byline
      : runtimeLabel(e().runtimeMinutes) || undefined
  return (
    <CardMenu
      id={e().libraryItemId}
      name={e().title.title}
      target={{ type: e().title.type, status: 'wishlist' }}
      onChanged={props.onChanged}
      class="w-32 shrink-0 snap-start md:w-36"
    >
      <Link
        to="/app/title/$id"
        params={{ id: e().libraryItemId }}
        class="block"
      >
        <Poster url={e().title.posterUrl} kind={kind()} frame />
        <p class="mt-2 line-clamp-2 text-sm font-medium">{e().title.title}</p>
        <Show when={detail()}>
          {(text) => <p class="truncate text-xs text-muted">{text()}</p>}
        </Show>
      </Link>
    </CardMenu>
  )
}

/** MUS-001, Home's Listening row: an album in progress, square, with its artist under it. */
export function ListeningCard(props: { entry: LibraryEntry }) {
  const e = () => props.entry
  return (
    <Link
      to="/app/title/$id"
      params={{ id: e().id }}
      class="block w-32 shrink-0 snap-start md:w-36"
    >
      <Poster url={e().title.posterUrl} kind="album" />
      <p class="mt-2 line-clamp-2 text-sm font-medium">{e().title.title}</p>
      <Show when={e().title.byline}>
        {(artist) => <p class="truncate text-xs text-muted">{artist()}</p>}
      </Show>
    </Link>
  )
}

/** Unfinished business: a dropped or long-paused title, why it is here, and where to resume. */
export function UnfinishedCard(props: {
  entry: UnfinishedEntry
  now: Date | null
  onChanged: (entry?: LibraryEntry) => void
}) {
  const e = () => props.entry
  const reason = () => {
    const now = props.now
    if (e().reason === 'dropped') return 'Dropped'
    return now ? unfinishedLabel(e(), now) : null
  }
  return (
    <CardMenu
      id={e().libraryItemId}
      name={e().title.title}
      target={{
        type: e().title.type,
        status: e().reason === 'dropped' ? 'dropped' : 'in_progress',
      }}
      onChanged={props.onChanged}
      class="w-32 shrink-0 snap-start md:w-36"
    >
      <Link
        to="/app/title/$id"
        params={{ id: e().libraryItemId }}
        class="block"
      >
        <Poster
          url={e().title.posterUrl}
          kind={kindOf(e().title.type, e().title.isAnime)}
          frame
        >
          <Show when={reason()}>
            {(text) => (
              <span class={`absolute top-2 left-2 ${chip}`}>{text()}</span>
            )}
          </Show>
        </Poster>
        <p class="mt-2 line-clamp-2 text-sm font-medium">{e().title.title}</p>
        <Show when={resumeLine(e())}>
          {(line) => <p class="text-xs text-muted">{line()}</p>}
        </Show>
      </Link>
    </CardMenu>
  )
}

/** Calendar row: one coming airing, badged "Tomorrow", "In 3 hours"… */
export function AiringCard(props: {
  entry: CalendarEntry
  when: string | null
  onChanged: (entry?: LibraryEntry) => void
}) {
  const e = () => props.entry
  const kind = () => badge(e())
  const meta = () => metaLine(e())
  return (
    <CardMenu
      id={e().libraryItemId}
      name={e().title.title}
      target={{ type: e().title.type }}
      onChanged={props.onChanged}
      class="w-56 shrink-0 snap-start"
      // The art's top corners carry its badges: the menu sits at its foot (art is 7rem tall).
      triggerClass="top-17 right-2"
    >
      <Link
        to="/app/title/$id"
        params={{ id: e().libraryItemId }}
        class="block transition-opacity"
        classList={{ 'opacity-60': e().watched }}
      >
        <div class="relative aspect-[2/1] overflow-hidden rounded-panel shadow-[0_0_0_1px_var(--line)]">
          <Art
            sources={[e().title.backdropUrl, e().title.posterUrl]}
            title={e().title.title}
          />
          <Show when={props.when}>
            {(text) => (
              <span class={`absolute top-2 left-2 ${chip}`}>{text()}</span>
            )}
          </Show>
          <Show when={kind()}>
            {(text) => (
              <Badge
                variant={e().kind === 'finale' ? 'ink' : 'default'}
                class="absolute top-2 right-2"
              >
                {text()}
              </Badge>
            )}
          </Show>
        </div>
        <p class="mt-2 truncate text-sm font-semibold">{e().title.title}</p>
        <p class="truncate text-xs text-muted">
          {[shortCode(e().season, e().number), e().episodeName]
            .filter(Boolean)
            .join(' · ')}
        </p>
        <Show when={meta()}>
          <p class="truncate text-xs text-muted">{meta()}</p>
        </Show>
      </Link>
    </CardMenu>
  )
}

/** DISC-001: a poster from a public row, on Home and on Discover. In the library it links to
 * the item; otherwise it carries search's add control and a list button. With `today` (the
 * viewer's local "YYYY-MM-DD"), the art wears the release-date badge. */
export function DiscoverCard(props: {
  hit: CatalogHit
  rowId: string
  adding: boolean
  onAdd: (status: LibraryStatus) => void
  onList: () => void
  today?: string | null
  /** `row` (default) sits in a scrolling row at a fixed width; `grid` fills its grid cell. */
  layout?: 'row' | 'grid'
  /** Lines under the title in place of the year, e.g. On air's next episode (DISC-003). */
  details?: JSX.Element
}) {
  const h = () => props.hit
  const kind = () => kindOf(h().type, h().isAnime)
  // An album leads with its artist; the year stands where other kinds name a kind.
  const meta = () =>
    (kind() === 'album' ? [h().byline, h().year] : [h().year, h().byline])
      .filter(Boolean)
      .join(' · ')
  const dateLabel = () =>
    props.today ? cardBadge(props.rowId, h().releaseDate, props.today) : null
  // A component, not one element: the poster is drawn in either branch below.
  const DateBadge = () => (
    <Show when={dateLabel()}>
      {(text) => (
        <span class="absolute bottom-1.5 left-1.5 rounded-full bg-accent px-2 py-0.5 text-2xs font-semibold text-on-accent">
          {text()}
        </span>
      )}
    </Show>
  )
  return (
    <div
      class={
        props.layout === 'grid' ? 'min-w-0' : 'w-32 shrink-0 snap-start md:w-36'
      }
    >
      <Show
        when={h().libraryItemId}
        fallback={
          <TitleLink
            hit={h()}
            class="relative block"
            aria-label={`${h().title}, details`}
          >
            <Poster url={h().posterUrl} kind={kind()} />
            <DateBadge />
          </TitleLink>
        }
      >
        {(id) => (
          <Link
            to="/app/title/$id"
            params={{ id: id() }}
            class="relative block"
            aria-label={`${h().title}, in your library`}
          >
            <Poster url={h().posterUrl} kind={kind()} />
            <DateBadge />
            <span
              class="absolute top-1.5 right-1.5 grid h-6 w-6 place-items-center rounded-full bg-accent text-xs font-bold text-on-accent"
              aria-hidden="true"
            >
              ✓
            </span>
          </Link>
        )}
      </Show>
      <p class="mt-2 line-clamp-2 text-sm font-medium">{h().title}</p>
      <Show
        when={props.details}
        fallback={
          <Show when={meta()}>
            <p class="truncate text-xs text-muted">{meta()}</p>
          </Show>
        }
      >
        {props.details}
      </Show>
      <Show
        when={!h().libraryItemId}
        fallback={
          <p class="mt-2 text-xs font-medium text-accent">In your library</p>
        }
      >
        <div class="mt-2 flex flex-wrap items-center gap-2">
          <AddControl
            hit={h()}
            adding={props.adding}
            onAdd={props.onAdd}
            idPrefix={`discover-${props.rowId}`}
          />
          <Button
            variant="ghost"
            size="bare"
            class="text-xs"
            onClick={() => props.onList()}
          >
            List…
          </Button>
        </div>
      </Show>
    </div>
  )
}
