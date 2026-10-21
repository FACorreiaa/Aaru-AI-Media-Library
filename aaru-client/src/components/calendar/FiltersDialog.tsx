import { For } from 'solid-js'
import { activeCount } from '../../lib/calendar/filters'
import type {
  CalendarFilter,
  KindFilter,
  OnlyFilter,
} from '../../lib/calendar/filters'
import { Button } from '../ui/button'
import { Dialog } from '../ui/dialog'
import { SegmentedControl, SegmentedControlItem } from '../ui/segmented-control'
import { Switch } from '../ui/switch'

/** The calendar's filters, loaded on first open so the page stays inside its size budget. */
export default function FiltersDialog(props: {
  filter: CalendarFilter
  onFilter: (filter: CalendarFilter) => void
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const set = (patch: Partial<CalendarFilter>) =>
    props.onFilter({ ...props.filter, ...patch })
  return (
    <Dialog
      ref={dialog}
      openOnMount
      placement="sheet"
      aria-label="Calendar filters"
      class="w-full max-w-[26rem]"
      onClose={() => props.onClose()}
    >
      <div class="flex flex-col gap-5 px-5 pt-4 pb-5">
        <div class="flex items-center justify-between">
          <h2 class="font-display text-2xl font-medium">Filters</h2>
          <Button
            variant="ghost"
            size="bare"
            class="text-sm"
            onClick={() => dialog?.close()}
          >
            Done
          </Button>
        </div>
        <Switch
          checked={props.filter.hideWatched}
          onChange={(hideWatched) => set({ hideWatched })}
          label="Hide watched"
          description="Only what is left to watch."
          class="flex items-start gap-3"
        />
        <Choice
          label="Episodes"
          value={props.filter.only ?? 'all'}
          options={[
            ['all', 'All'],
            ['premieres', 'Premieres'],
            ['finales', 'Finales'],
          ]}
          onChange={(value) =>
            set({ only: value === 'all' ? undefined : (value as OnlyFilter) })
          }
        />
        <Choice
          label="Kind"
          value={props.filter.kind ?? 'all'}
          options={[
            ['all', 'All'],
            ['show', 'Shows'],
            ['anime', 'Anime'],
          ]}
          onChange={(value) =>
            set({ kind: value === 'all' ? undefined : (value as KindFilter) })
          }
        />
        <Button
          variant="quiet"
          size="sm"
          class="self-start"
          disabled={activeCount(props.filter) === 0}
          onClick={() => props.onFilter({ hideWatched: false })}
        >
          Clear filters
        </Button>
      </div>
    </Dialog>
  )
}

function Choice(props: {
  label: string
  value: string
  options: [string, string][]
  onChange: (value: string) => void
}) {
  return (
    <div>
      <p class="mb-2 text-sm font-medium">{props.label}</p>
      <SegmentedControl
        class="flex w-fit rounded-full border border-line p-0.5"
        aria-label={props.label}
        value={props.value}
        onChange={props.onChange}
      >
        <For each={props.options}>
          {([value, label]) => (
            <SegmentedControlItem value={value} class="min-h-9 px-3 text-sm">
              {label}
            </SegmentedControlItem>
          )}
        </For>
      </SegmentedControl>
    </div>
  )
}
