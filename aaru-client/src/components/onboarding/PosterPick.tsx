import { For, Show, createSignal, onCleanup } from 'solid-js'
import {
  Badge,
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '~/components/ui'
import { cn } from '~/lib/utils'
import type {
  CatalogHit,
  LibraryStatus,
  MediaKind,
} from '../../lib/library/model'
import { dots } from '../CardMenu'
import { Poster } from '../Poster'

// One poster on a first-run screen (ONB-001): a tap does the screen's one thing (cycle a status,
// star, plan); the chip on the art says what it is now. With `menu`, a right-click, a long press
// on touch or the "⋯" opens the status menu and Remove, as Home's cards do (CardMenu).

/** A touch held this long opens the menu instead of tapping. */
const LONG_PRESS_MS = 500
/** A finger that moves this far is scrolling, not pressing. */
const PRESS_SLOP_PX = 10

export function PosterPick(props: {
  hit: CatalogHit
  kind: MediaKind
  /** The chip on the art, e.g. "Watched" or "★ 2". */
  chip?: string | null
  selected: boolean
  /** Already in the library: shown, never sent again. */
  locked?: boolean
  /** A line under the year, e.g. "In your library". */
  note?: string
  onTap: () => void
  menu?: {
    current: LibraryStatus | null
    options: Array<{ status: LibraryStatus; label: string }>
    onSet: (status: LibraryStatus | null) => void
  }
  layout?: 'row' | 'grid'
}) {
  const [open, setOpen] = createSignal(false)
  let timer: ReturnType<typeof setTimeout> | undefined
  let start: { x: number; y: number } | null = null
  /** A long press opened the menu: the click the touch ends with is not a tap. */
  let pressed = false

  const meta = () =>
    (props.kind === 'album'
      ? [props.hit.byline, props.hit.year]
      : [props.hit.year, props.hit.byline]
    )
      .filter(Boolean)
      .join(' · ')

  function cancelPress() {
    clearTimeout(timer)
    timer = undefined
    start = null
  }
  onCleanup(cancelPress)

  function pointerDown(event: PointerEvent) {
    pressed = false
    if (!props.menu || props.locked || event.pointerType !== 'touch') return
    start = { x: event.clientX, y: event.clientY }
    timer = setTimeout(() => {
      pressed = true
      cancelPress()
      setOpen(true)
    }, LONG_PRESS_MS)
  }

  function pointerMove(event: PointerEvent) {
    if (
      start &&
      Math.hypot(event.clientX - start.x, event.clientY - start.y) >
        PRESS_SLOP_PX
    )
      cancelPress()
  }

  const label = () =>
    [
      props.hit.title,
      props.hit.year,
      props.locked ? 'in your library' : props.chip,
    ]
      .filter(Boolean)
      .join(', ')

  return (
    <div
      class={cn(
        'group/card relative [-webkit-touch-callout:none] [@media(hover:none)]:select-none',
        props.layout === 'grid'
          ? 'min-w-0'
          : 'w-32 shrink-0 snap-start md:w-40',
      )}
      onContextMenu={(event) => {
        if (!props.menu || props.locked) return
        event.preventDefault()
        cancelPress()
        setOpen(true)
      }}
      onPointerDown={pointerDown}
      onPointerMove={pointerMove}
      onPointerUp={cancelPress}
      onPointerCancel={cancelPress}
    >
      <Button
        variant="ghost"
        size="bare"
        disabled={props.locked}
        aria-pressed={props.selected}
        aria-label={label()}
        class="block w-full rounded-field p-0 text-left font-normal text-ink hover:text-ink disabled:opacity-100"
        onClick={() => {
          if (pressed) {
            pressed = false
            return
          }
          props.onTap()
        }}
      >
        <Poster
          url={props.hit.posterUrl}
          kind={props.kind}
          frame={props.layout === 'grid'}
          class={props.locked ? 'opacity-60' : undefined}
        >
          {/* Over the art, inside its corners: a ring outside would be clipped by the row. */}
          <Show when={props.selected}>
            <span
              aria-hidden="true"
              class="pointer-events-none absolute inset-0 rounded-[inherit] ring-3 ring-accent ring-inset"
            />
          </Show>
          <Show when={props.chip}>
            {(chip) => (
              <Badge
                variant={props.selected ? 'default' : 'scrim'}
                class="absolute bottom-1.5 left-1.5 max-w-[calc(100%-0.75rem)] truncate"
              >
                {chip()}
              </Badge>
            )}
          </Show>
        </Poster>
        <span class="mt-2 block truncate text-sm font-medium">
          {props.hit.title}
        </span>
        <Show when={props.note ?? meta()}>
          {(text) => (
            <span class="block truncate text-xs text-muted">{text()}</span>
          )}
        </Show>
      </Button>
      <Show when={props.menu && !props.locked ? props.menu : undefined}>
        {(menu) => (
          <DropdownMenu
            placement="bottom-end"
            open={open()}
            onOpenChange={setOpen}
          >
            <DropdownMenuTrigger
              as={Button}
              variant="ghost"
              size="bare"
              aria-label={`Status for ${props.hit.title}`}
              class="absolute top-1.5 right-1.5 size-9 bg-scrim text-on-scrim opacity-0 transition-opacity group-focus-within/card:opacity-100 group-hover/card:opacity-100 focus-visible:opacity-100 data-[expanded]:opacity-100 [@media(hover:none)]:opacity-100"
            >
              {dots()}
            </DropdownMenuTrigger>
            <DropdownMenuPortal>
              <DropdownMenuContent class="min-w-48 rounded-panel border-line bg-paper p-1">
                <For each={menu().options}>
                  {(option) => (
                    <DropdownMenuItem
                      class="min-h-10 justify-between gap-4 rounded-field px-3"
                      onSelect={() => menu().onSet(option.status)}
                    >
                      {option.label}
                      <Show when={menu().current === option.status}>
                        <span aria-label="current">✓</span>
                      </Show>
                    </DropdownMenuItem>
                  )}
                </For>
                <Show when={menu().current}>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem
                    class="min-h-10 rounded-field px-3 text-danger"
                    onSelect={() => menu().onSet(null)}
                  >
                    Remove
                  </DropdownMenuItem>
                </Show>
              </DropdownMenuContent>
            </DropdownMenuPortal>
          </DropdownMenu>
        )}
      </Show>
    </div>
  )
}
