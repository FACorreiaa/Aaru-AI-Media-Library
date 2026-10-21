import { For, Show, createSignal, lazy } from 'solid-js'
import { activeCount } from '../../lib/calendar/filters'
import type { CalendarFilter, CalendarView } from '../../lib/calendar/filters'
import { Badge } from '../ui/badge'
import { Button } from '../ui/button'
import { SegmentedControl, SegmentedControlItem } from '../ui/segmented-control'

const FiltersDialog = lazy(() => import('./FiltersDialog'))

const VIEWS: { value: CalendarView; label: string }[] = [
  { value: 'week', label: 'Week' },
  { value: 'month', label: 'Month' },
  { value: 'missed', label: 'Missed' },
]

/** The calendar's controls (CAL-002): the view, day and week steps, Today, a date to jump to,
 *  and filters that apply to whatever is loaded. */
export function CalendarToolbar(props: {
  view: CalendarView
  ready: boolean
  /** The selected day, for the date field. */
  selected: string
  filter: CalendarFilter
  missedCount: number
  onView: (view: CalendarView) => void
  onStep: (days: number) => void
  onToday: () => void
  onGoTo: (day: string) => void
  onFilter: (filter: CalendarFilter) => void
}) {
  const [filtersOpen, setFiltersOpen] = createSignal(false)
  const count = () => activeCount(props.filter)
  const week = () => props.view === 'week'

  return (
    <div class="flex flex-wrap items-center gap-2">
      <SegmentedControl
        class="flex rounded-full border border-line p-0.5"
        aria-label="Calendar view"
        value={props.view}
        onChange={(next) => props.onView(next as CalendarView)}
      >
        <For each={VIEWS}>
          {(option) => (
            <SegmentedControlItem
              value={option.value}
              class="min-h-9 gap-1.5 px-3 text-sm"
            >
              {option.label}
              <Show when={option.value === 'missed' && props.missedCount > 0}>
                <Badge size="xs" tone="accent">
                  {props.missedCount}
                </Badge>
              </Show>
            </SegmentedControlItem>
          )}
        </For>
      </SegmentedControl>

      <Show when={props.view !== 'missed'}>
        <nav class="flex items-center gap-1" aria-label="Move through days">
          <Show when={week()}>
            <Button
              variant="quiet"
              size="icon"
              disabled={!props.ready}
              aria-label="Previous week"
              aria-keyshortcuts="PageUp"
              onClick={() => props.onStep(-7)}
            >
              «
            </Button>
            <Button
              variant="quiet"
              size="icon"
              disabled={!props.ready}
              aria-label="Previous day"
              aria-keyshortcuts="ArrowLeft"
              onClick={() => props.onStep(-1)}
            >
              ‹
            </Button>
          </Show>
          <Button
            variant="quiet"
            size="sm"
            class="min-h-11"
            disabled={!props.ready}
            onClick={() => props.onToday()}
          >
            Today
          </Button>
          <Show when={week()}>
            <Button
              variant="quiet"
              size="icon"
              disabled={!props.ready}
              aria-label="Next day"
              aria-keyshortcuts="ArrowRight"
              onClick={() => props.onStep(1)}
            >
              ›
            </Button>
            <Button
              variant="quiet"
              size="icon"
              disabled={!props.ready}
              aria-label="Next week"
              aria-keyshortcuts="PageDown"
              onClick={() => props.onStep(7)}
            >
              »
            </Button>
          </Show>
          <label class="relative">
            <span class="sr-only">Go to date</span>
            <input
              type="date"
              class="min-h-11 rounded-full border border-line bg-paper px-3 text-sm"
              value={props.selected}
              disabled={!props.ready}
              onChange={(event) => {
                const day = event.currentTarget.value
                if (day) props.onGoTo(day)
              }}
            />
          </label>
        </nav>
      </Show>

      <Button
        variant={count() > 0 ? 'ink' : 'quiet'}
        size="sm"
        class="min-h-11"
        aria-haspopup="dialog"
        onClick={() => setFiltersOpen(true)}
      >
        Filters
        <Show when={count() > 0}>
          <Badge size="xs" class="ml-1.5">
            {count()}
          </Badge>
        </Show>
      </Button>

      <Show when={filtersOpen()}>
        <FiltersDialog
          filter={props.filter}
          onFilter={props.onFilter}
          onClose={() => setFiltersOpen(false)}
        />
      </Show>
    </div>
  )
}

/** The filters as removable chips under the toolbar, so what is hidden is never a mystery. */
export function FilterChips(props: {
  filter: CalendarFilter
  onFilter: (filter: CalendarFilter) => void
}) {
  const chips = () =>
    [
      props.filter.hideWatched && {
        label: 'Watched hidden',
        clear: { ...props.filter, hideWatched: false },
      },
      props.filter.only && {
        label:
          props.filter.only === 'premieres' ? 'Premieres only' : 'Finales only',
        clear: { ...props.filter, only: undefined },
      },
      props.filter.kind && {
        label: props.filter.kind === 'anime' ? 'Anime only' : 'Shows only',
        clear: { ...props.filter, kind: undefined },
      },
    ].filter((chip): chip is { label: string; clear: CalendarFilter } => !!chip)
  return (
    <Show when={chips().length > 0}>
      <ul class="mt-3 flex flex-wrap gap-2" aria-label="Active filters">
        <For each={chips()}>
          {(chip) => (
            <li>
              <button
                type="button"
                class="flex min-h-9 items-center gap-1.5 rounded-full bg-ink/10 px-3 text-sm font-medium hover:bg-ink/15"
                aria-label={`Remove filter: ${chip.label}`}
                onClick={() => props.onFilter(chip.clear)}
              >
                {chip.label}
                <span aria-hidden="true">×</span>
              </button>
            </li>
          )}
        </For>
      </ul>
    </Show>
  )
}
