import { For, Show } from 'solid-js'
import type { MessageComponent } from '../../lib/groups/agent'
import { kindName, kindOf } from '../../lib/library/model'
import { AddToLibrary } from '../AddToLibrary'
import { OwlMark } from '../Brand'
import { Poster } from '../Poster'

// GRP-011 on the web: how Aaru appears in a channel. It wears the owl, says it is an
// assistant, breathes while it works, and answers with title cards whose buttons act for
// whoever taps them.

/** Aaru's avatar: the owl's head on the night disc, at the size of a member's monogram. */
export function AaruAvatar(props: { size?: 'sm' | 'md'; breathing?: boolean }) {
  return (
    <OwlMark
      class={props.size === 'sm' ? 'size-7' : 'size-10'}
      breathing={props.breathing}
    />
  )
}

/** The small tag beside Aaru's name. */
export function AssistantTag() {
  return (
    <span class="rounded bg-medallion/25 px-1.5 py-0.5 text-[10px] font-semibold tracking-wide text-muted uppercase">
      Assistant
    </span>
  )
}

/** "Replying to @ana: what should we…" above an Aaru reply. */
export function ReplyLine(props: { who: string; text: string }) {
  return (
    <p class="mb-0.5 truncate text-xs text-muted">
      <span aria-hidden="true">↳ </span>
      Replying to <span class="font-medium text-ink/80">{props.who}</span>
      <Show when={props.text}>: {props.text}</Show>
    </p>
  )
}

/** The row at the bottom of the channel while Aaru works on an answer. */
export function ThinkingRow() {
  return (
    <div
      class="mt-3 flex items-center gap-3 px-4 md:px-6"
      role="status"
      aria-live="polite"
    >
      <AaruAvatar breathing />
      <p class="text-sm text-muted">Aaru is thinking…</p>
    </div>
  )
}

/**
 * The title cards on an Aaru reply. "Add to my library" is the reader's own tap, the same
 * journaled add as anywhere else in Aaru; Aaru itself never adds anything.
 */
export function AgentCards(props: { cards: MessageComponent[] }) {
  return (
    <ul class="mt-2 grid max-w-xl gap-2 sm:grid-cols-2">
      <For each={props.cards}>
        {(card) => {
          const kind = () => kindOf(card.title.type, card.title.isAnime)
          return (
            <li class="flex gap-3 rounded-xl border border-line bg-paper p-2">
              <div class="w-12 shrink-0">
                <Poster url={card.title.posterUrl} kind={kind()} class="w-12" />
              </div>
              <div class="flex min-w-0 flex-1 flex-col">
                <p class="truncate text-sm font-semibold">{card.title.title}</p>
                <p class="truncate text-xs text-muted">
                  {[
                    kind() === 'album' ? card.title.byline : undefined,
                    card.title.year,
                    kindName(kind()),
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </p>
                <div class="mt-auto pt-1.5">
                  <AddToLibrary
                    title={card.title}
                    name={card.title.title}
                    look="card"
                  />
                </div>
              </div>
            </li>
          )
        }}
      </For>
    </ul>
  )
}
