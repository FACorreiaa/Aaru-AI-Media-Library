import { Show, createSignal } from 'solid-js'
import { spoilerChoiceLabel, validEpisode } from '../../lib/groups/kinds'
import type { SpoilerChoice } from '../../lib/groups/kinds'
import { Menu, MenuItem } from './shell'

/**
 * SpoilerVeil (GRP-007): a message that may spoil what the reader has not watched yet, folded
 * until they ask. Lifting it is local; nobody is told.
 */
export function SpoilerVeil(props: { onShow: () => void }) {
  return (
    <p class="mt-0.5 flex items-center gap-2 rounded-lg bg-surface px-3 py-1.5 text-sm text-muted">
      <span aria-hidden="true">◐</span>
      <span>May spoil what you haven't watched yet ·</span>
      <button
        type="button"
        onClick={() => props.onShow()}
        class="font-medium text-accent hover:underline"
      >
        Show
      </button>
    </p>
  )
}

/**
 * Above the composer in a title channel: what the next message is marked as. By default it is
 * marked at my own progress, which only I see; members behind it see it veiled.
 */
export function SpoilerControl(props: {
  value: SpoilerChoice
  onChange: (choice: SpoilerChoice) => void
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
    <div class="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open()}
        onClick={() => setOpen(!open())}
        title="Members who haven't watched this far see it veiled. Only you see the mark."
        class={`flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${props.value.mode === 'auto' ? 'bg-surface text-muted hover:text-ink' : 'bg-accent/15 text-accent'}`}
      >
        <span aria-hidden="true">◐</span>
        {spoilerChoiceLabel(props.value)}
        <span aria-hidden="true">▾</span>
      </button>
      <Menu
        open={open()}
        onClose={() => setOpen(false)}
        class="bottom-full left-0 mb-1 w-64"
      >
        <MenuItem onSelect={() => choose({ mode: 'auto' })}>
          <span class="block font-medium">Mark at my progress</span>
          <span class="block text-xs text-muted">
            Hidden from whoever is behind you.
          </span>
        </MenuItem>
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
            <label class="flex items-center gap-1">
              S
              <input
                type="number"
                min="0"
                inputmode="numeric"
                value={season()}
                aria-label="Season"
                onInput={(e) => setSeason(e.currentTarget.value)}
                class="w-12 rounded-md border-0 bg-surface px-1.5 py-1 text-sm"
              />
            </label>
            <label class="flex items-center gap-1">
              E
              <input
                type="number"
                min="1"
                inputmode="numeric"
                value={episode()}
                aria-label="Episode"
                onInput={(e) => setEpisode(e.currentTarget.value)}
                class="w-12 rounded-md border-0 bg-surface px-1.5 py-1 text-sm"
              />
            </label>
            <button
              type="submit"
              disabled={!episodeOk()}
              class="ml-auto rounded-full bg-accent px-3 py-1 font-semibold text-on-accent disabled:opacity-40"
            >
              Set
            </button>
          </div>
        </form>
        <MenuItem onSelect={() => choose({ mode: 'ending' })}>
          Spoils the ending
        </MenuItem>
        <MenuItem onSelect={() => choose({ mode: 'free' })}>
          <span class="block">No spoilers</span>
          <Show when={props.value.mode !== 'free'}>
            <span class="block text-xs text-muted">Everyone sees it.</span>
          </Show>
        </MenuItem>
      </Menu>
    </div>
  )
}
