import { activeCount } from '../../lib/calendar/filters'
import type {
  CalendarFilter,
  KindFilter,
  OnlyFilter,
} from '../../lib/calendar/filters'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  Switch,
  SwitchControl,
  SwitchDescription,
  SwitchInput,
  SwitchLabel,
  SwitchThumb,
} from '~/components/ui'
import { Segmented } from '../Segmented'

/** The calendar's filters, loaded on first open so the page stays inside its size budget. */
export default function FiltersDialog(props: {
  filter: CalendarFilter
  onFilter: (filter: CalendarFilter) => void
  /** Defaults to true; the parent keeps it mounted with false so its exit plays (WEB-011). */
  open?: boolean
  onClose: () => void
}) {
  const set = (patch: Partial<CalendarFilter>) =>
    props.onFilter({ ...props.filter, ...patch })
  return (
    <Dialog
      open={props.open ?? true}
      onOpenChange={(open) => {
        if (!open) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent
          placement="sheet"
          showCloseButton={false}
          aria-label="Calendar filters"
          class="block gap-0 p-0 w-full max-w-[26rem] sm:max-w-[26rem]"
        >
          <div class="flex flex-col gap-5 px-5 pt-4 pb-5">
            <div class="flex items-center justify-between">
              <h2 class="font-display text-2xl font-medium">Filters</h2>
              <Button
                variant="ghost"
                size="bare"
                class="text-sm"
                onClick={() => props.onClose()}
              >
                Done
              </Button>
            </div>
            <Switch
              checked={props.filter.hideWatched}
              onChange={(hideWatched) => set({ hideWatched })}
              class="flex items-start gap-3"
            >
              <SwitchInput />
              <SwitchControl>
                <SwitchThumb />
              </SwitchControl>
              <span>
                <SwitchLabel class="cursor-pointer">Hide watched</SwitchLabel>
                <SwitchDescription class="block text-xs">
                  Only what is left to watch.
                </SwitchDescription>
              </span>
            </Switch>
            <Choice
              label="Episodes"
              value={props.filter.only ?? 'all'}
              options={[
                ['all', 'All'],
                ['premieres', 'Premieres'],
                ['finales', 'Finales'],
              ]}
              onChange={(value) =>
                set({
                  only: value === 'all' ? undefined : (value as OnlyFilter),
                })
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
                set({
                  kind: value === 'all' ? undefined : (value as KindFilter),
                })
              }
            />
            <Button
              variant="quiet"
              size="sm"
              class="self-start"
              disabled={activeCount(props.filter) === 0}
              onClick={() =>
                props.onFilter({
                  hideWatched: false,
                  group: props.filter.group,
                })
              }
            >
              Clear filters
            </Button>
          </div>
        </DialogContent>
      </DialogPortal>
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
      <Segmented
        label={props.label}
        itemClass="flex min-h-9 items-center px-3 text-sm"
        options={props.options.map(([value, label]) => ({ value, label }))}
        value={props.value}
        onChange={props.onChange}
      />
    </div>
  )
}
