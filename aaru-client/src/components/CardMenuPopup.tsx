import { useNavigate } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  Button,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuTrigger,
} from '~/components/ui'
import type { LibraryEntry } from '../lib/library/model'
import { markLabel } from '../lib/title/model'
import type { MarkTarget } from '../lib/title/model'
import { markItemWatched } from './mark-watched'
import { toastFailure } from './undo-toast'

// CardMenu's menu itself, loaded the first time a card asks for it: the Library grid and Home's
// rows do not carry the menu primitive (and the writes behind it) on their first load.

export default function CardMenuPopup(props: {
  id: string
  name: string
  target: MarkTarget
  onChanged: (entry?: LibraryEntry) => void
  open: boolean
  onOpenChange: (open: boolean) => void
  triggerClass: string
  icon: JSX.Element
}) {
  const navigate = useNavigate()
  const [busy, setBusy] = createSignal(false)
  const label = () => markLabel(props.target)

  async function mark() {
    if (busy()) return
    setBusy(true)
    try {
      await markItemWatched(
        { id: props.id, name: props.name, target: props.target },
        (entry) => props.onChanged(entry),
      )
    } catch (err) {
      toastFailure(err, `${props.name} was not marked watched.`)
    } finally {
      setBusy(false)
    }
  }

  return (
    <DropdownMenu
      placement="bottom-end"
      open={props.open}
      onOpenChange={props.onOpenChange}
    >
      <DropdownMenuTrigger
        as={Button}
        variant="ghost"
        size="bare"
        aria-label={`More for ${props.name}`}
        class={props.triggerClass}
      >
        {props.icon}
      </DropdownMenuTrigger>
      <DropdownMenuPortal>
        <DropdownMenuContent class="min-w-52 rounded-panel border-line bg-paper p-1">
          <Show when={label()}>
            {(text) => (
              <DropdownMenuItem
                class="min-h-10 rounded-[10px] px-3"
                disabled={busy()}
                onSelect={() => void mark()}
              >
                {text()}
              </DropdownMenuItem>
            )}
          </Show>
          <DropdownMenuItem
            class="min-h-10 rounded-[10px] px-3"
            onSelect={() =>
              void navigate({ to: '/app/title/$id', params: { id: props.id } })
            }
          >
            Open
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenuPortal>
    </DropdownMenu>
  )
}
