import { For, Index, Show, createEffect, createSignal, on } from 'solid-js'
import {
  SEASON_KINDS,
  canShift,
  countLabel,
  direction,
  monthSpan,
  pageKey,
  seasonLabel,
  shiftSeason,
} from '../lib/discover/season'
import type { SeasonKey, SeasonKind, SeasonPage } from '../lib/discover/season'
import { getDiscoverSeason } from '../lib/home/server'
import { hitKey } from '../lib/library/model'
import { play, slideIn } from '../lib/motion'
import { createDiscoverAdder } from './DiscoverRows'
import { DiscoverCard } from './HomeRows'
import { Alert } from './ui/alert'
import { Button } from './ui/button'
import { SegmentedControl, SegmentedControlItem } from './ui/segmented-control'

const SKELETON_CARDS = 12

/**
 * DISC-002: one season as an object. The season's name is the page's headline, flanked by
 * the steps to the seasons either side; the kind switch picks what the season lists; the
 * grid is that season's titles, popular first, each addable in place. Flipping seasons slides
 * the new one in from the side it lies on. Pages already seen come back from memory at once.
 */
export function SeasonBrowser(props: {
  kind: SeasonKind
  season: SeasonKey
  /** The viewer's local "YYYY-MM-DD": the date badges and the latest season allowed. */
  today: string
  onChange: (kind: SeasonKind, season: SeasonKey) => void
  onProblem: (message: string | null) => void
}) {
  // Every page fetched this visit, by kind, season and page number.
  const [pages, setPages] = createSignal<ReadonlyMap<string, SeasonPage>>(
    new Map(),
  )
  const [shown, setShown] = createSignal(1)
  const [loading, setLoading] = createSignal(false)
  const [failed, setFailed] = createSignal<string | null>(null)
  let grid: HTMLDivElement | undefined
  let heading: HTMLDivElement | undefined
  let latest = 0

  const pageAt = (n: number) =>
    pages().get(pageKey(props.kind, props.season, n))
  const loaded = () =>
    Array.from({ length: shown() }, (_, i) => pageAt(i + 1)).filter(
      (page): page is SeasonPage => page !== undefined,
    )
  const first = () => pageAt(1)
  const items = () => loaded().flatMap((page) => page.items)
  const hasMore = () => loaded().at(-1)?.hasMore ?? false
  const meta = () =>
    [
      monthSpan(props.season.season),
      first() ? countLabel(props.kind, first()?.total) : null,
    ]
      .filter(Boolean)
      .join(' · ')

  async function fetchPage(n: number) {
    const key = pageKey(props.kind, props.season, n)
    if (pages().has(key)) return
    const request = ++latest
    setLoading(true)
    setFailed(null)
    try {
      const page = await getDiscoverSeason({
        data: {
          kind: props.kind,
          season: props.season.season,
          year: props.season.year,
          page: n,
        },
      })
      setPages((current) => new Map(current).set(key, page))
    } catch (error) {
      if (request === latest)
        setFailed(
          error instanceof Error
            ? error.message
            : 'This season could not be loaded.',
        )
    } finally {
      if (request === latest) setLoading(false)
    }
  }

  // A new season or kind: back to its first page, fetched unless it is already here, and
  // brought in from the side it lies on (a kind change fades, it has no side).
  createEffect(
    on(
      () => [props.kind, props.season] as const,
      ([kind, season], previous) => {
        setShown(1)
        void fetchPage(1)
        if (!previous) return
        const [previousKind, previousSeason] = previous
        const way = direction(previousSeason, season)
        for (const el of [grid, way === 0 ? undefined : heading]) {
          if (!el) continue
          if (way !== 0) void slideIn(el, way)
          else if (kind !== previousKind)
            void play(el, { opacity: [0, 1] }, 0.2)
        }
      },
    ),
  )

  const adder = createDiscoverAdder({
    onAdded: (key, entry) =>
      setPages((current) => {
        const next = new Map<string, SeasonPage>()
        for (const [k, page] of current) {
          next.set(k, {
            ...page,
            items: page.items.map((hit) =>
              hitKey(hit) === key ? { ...hit, libraryItemId: entry.id } : hit,
            ),
          })
        }
        return next
      }),
    onProblem: (message) => props.onProblem(message),
  })

  const step = (way: 1 | -1) => shiftSeason(props.season, way)
  const arrow =
    'grid size-11 shrink-0 place-items-center rounded-full border border-line text-xl text-ink transition-[background-color,transform] hover:bg-surface motion-safe:active:scale-[0.96] disabled:opacity-30 disabled:hover:bg-transparent'

  return (
    <section class="mt-8" aria-label="Seasons">
      <div class="flex items-center justify-between gap-3">
        <button
          type="button"
          class={arrow}
          aria-label={`Previous season, ${seasonLabel(step(-1))}`}
          disabled={!canShift(props.season, -1, props.today)}
          onClick={() => props.onChange(props.kind, step(-1))}
        >
          ‹
        </button>
        <div ref={heading} class="min-w-0 text-center">
          <h2
            class="font-display text-5xl font-medium tracking-tight tabular-nums md:text-6xl"
            aria-live="polite"
          >
            {seasonLabel(props.season)}
          </h2>
          <p class="mt-2 text-sm text-muted">{meta()}</p>
        </div>
        <button
          type="button"
          class={arrow}
          aria-label={`Next season, ${seasonLabel(step(1))}`}
          disabled={!canShift(props.season, 1, props.today)}
          onClick={() => props.onChange(props.kind, step(1))}
        >
          ›
        </button>
      </div>

      <div class="mt-6 flex justify-center overflow-x-auto">
        <SegmentedControl
          class="flex shrink-0 gap-1.5 text-sm"
          aria-label="What to list"
          value={props.kind}
          onChange={(kind) => props.onChange(kind as SeasonKind, props.season)}
        >
          <For each={SEASON_KINDS}>
            {(option) => (
              <SegmentedControlItem
                value={option.kind}
                variant="chip"
                class="px-4 py-1.5 whitespace-nowrap"
              >
                {option.label}
              </SegmentedControlItem>
            )}
          </For>
        </SegmentedControl>
      </div>

      <Show when={failed()}>
        {(message) => <Alert class="mt-6">{message()}</Alert>}
      </Show>
      <Show when={first()?.unavailable}>
        <p class="mt-8 rounded-panel bg-surface px-4 py-3 text-center text-sm text-muted">
          {props.kind === 'anime' ? 'AniList' : 'TMDB'} isn’t answering right
          now. Try this season again in a few minutes.
        </p>
      </Show>

      <div
        ref={grid}
        class="mt-8 grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6"
        aria-busy={loading()}
      >
        <Show
          when={first()}
          fallback={
            <Show when={!failed()}>
              <Index each={Array.from({ length: SKELETON_CARDS })}>
                {() => (
                  <div aria-hidden="true">
                    <div class="aspect-[2/3] rounded-field bg-surface" />
                    <div class="mt-2 h-3.5 w-4/5 rounded-full bg-surface" />
                    <div class="mt-1.5 h-3 w-2/5 rounded-full bg-surface" />
                  </div>
                )}
              </Index>
            </Show>
          }
        >
          <Index each={items()}>
            {(hit) => (
              <DiscoverCard
                hit={hit()}
                rowId={`season_${props.kind}`}
                today={props.today}
                layout="grid"
                adding={adder.isAdding(hit())}
                onAdd={(status) => void adder.add(hit(), status)}
                onList={() => adder.openList(hit())}
              />
            )}
          </Index>
        </Show>
      </div>

      <Show when={first() && !first()?.unavailable && items().length === 0}>
        <p class="mt-2 text-center text-muted">
          Nothing listed for {seasonLabel(props.season)} yet.
        </p>
      </Show>

      <Show when={hasMore()}>
        <div class="mt-10 flex justify-center">
          <Button
            variant="quiet"
            disabled={loading()}
            onClick={() => {
              const next = shown() + 1
              void fetchPage(next).then(() => setShown(next))
            }}
          >
            {loading() ? 'Loading…' : 'Show more'}
          </Button>
        </div>
      </Show>
      <adder.ListDialog />
    </section>
  )
}
