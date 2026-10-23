import { Show, createSignal } from 'solid-js'
import type { JSX } from 'solid-js'
import {
  Button,
  Popover,
  PopoverContent,
  PopoverPortal,
  PopoverTrigger,
  TextField,
  TextFieldInput,
  TextFieldLabel,
} from '~/components/ui'
import { spoilerChoiceLabel, validEpisode } from '../../lib/groups/kinds'
import type { SpoilerChoice } from '../../lib/groups/kinds'

// Its own module, so a page that only reads posts (the Board) does not load the popover below.
export { SpoilerVeil } from './SpoilerVeil'

function Choice(props: { onSelect: () => void; children: JSX.Element }) {
  return (
    <Button
      variant="ghost"
      size="bare"
      onClick={() => props.onSelect()}
      class="block w-full rounded-none px-4 py-2 text-left font-normal text-ink hover:bg-surface hover:text-ink"
    >
      {props.children}
    </Button>
  )
}

const numberClass = 'min-h-8 w-14 rounded-md border-0 bg-surface px-1.5 text-sm'

/**
 * Above the composer in a title channel: what the next group message is marked as. By default
 * it is marked at my own progress, which only I see; members behind it see it veiled. A Popover
 * (WEB-003): it holds an episode form, which a menu cannot.
 */
export function SpoilerControl(props: {
  value: SpoilerChoice
  onChange: (choice: SpoilerChoice) => void
  /** The trigger's tooltip; the Board's readers are friends, not members. */
  hint?: string
}) {
  const [open, setOpen] = createSignal(false)
  const [season, setSeason] = createSignal('1')
  const [episode, setEpisode] = createSignal('1')
  const episodeOk = () => validEpisode(Number(season()), Number(episode()))

  function choose(choice: SpoilerChoice) {
    props.onChange(choice)
    setOpen(false)
  }

  return (
    <Popover open={open()} onOpenChange={setOpen} placement="top-start">
      <PopoverTrigger
        title={
          props.hint ??
          "Members who haven't watched this far see it veiled. Only you see the mark."
        }
        class={`flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${props.value.mode === 'auto' ? 'bg-surface text-muted hover:text-ink' : 'bg-accent/15 text-accent'}`}
      >
        <span aria-hidden="true">◐</span>
        {spoilerChoiceLabel(props.value)}
        <span aria-hidden="true">▾</span>
      </PopoverTrigger>
      <PopoverPortal>
        <PopoverContent
          aria-label="Spoiler mark"
          class="w-64 overflow-hidden rounded-panel border-line bg-paper p-0 py-1 text-sm text-ink shadow-lift"
        >
          <Choice onSelect={() => choose({ mode: 'auto' })}>
            <span class="block font-medium">Mark at my progress</span>
            <span class="block text-xs text-muted">
              Hidden from whoever is behind you.
            </span>
          </Choice>
          <form
            class="border-y border-line px-4 py-2"
            onSubmit={(e) => {
              e.preventDefault()
              if (!episodeOk()) return
              choose({
                mode: 'episode',
                season: Number(season()),
                episode: Number(episode()),
              })
            }}
          >
            <span class="block font-medium">Spoils up to an episode</span>
            <div class="mt-1.5 flex items-center gap-1.5 text-xs">
              <TextField
                value={season()}
                onChange={setSeason}
                class="flex w-auto flex-row items-center gap-1"
              >
                <TextFieldLabel class="text-xs" aria-hidden="true">
                  S
                </TextFieldLabel>
                <TextFieldInput
                  type="number"
                  min="0"
                  inputmode="numeric"
                  aria-label="Season"
                  class={numberClass}
                />
              </TextField>
              <TextField
                value={episode()}
                onChange={setEpisode}
                class="flex w-auto flex-row items-center gap-1"
              >
                <TextFieldLabel class="text-xs" aria-hidden="true">
                  E
                </TextFieldLabel>
                <TextFieldInput
                  type="number"
                  min="1"
                  inputmode="numeric"
                  aria-label="Episode"
                  class={numberClass}
                />
              </TextField>
              <Button
                type="submit"
                size="xs"
                disabled={!episodeOk()}
                class="ml-auto"
              >
                Set
              </Button>
            </div>
          </form>
          <Choice onSelect={() => choose({ mode: 'ending' })}>
            Spoils the ending
          </Choice>
          <Choice onSelect={() => choose({ mode: 'free' })}>
            <span class="block">No spoilers</span>
            <Show when={props.value.mode !== 'free'}>
              <span class="block text-xs text-muted">Everyone sees it.</span>
            </Show>
          </Choice>
        </PopoverContent>
      </PopoverPortal>
    </Popover>
  )
}
