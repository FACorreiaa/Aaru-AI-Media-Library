import { Link } from '@tanstack/solid-router'
import { For, Show, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import type { MessageComponent } from '../../lib/groups/agent'
import { addTitleToLibrary } from '../../lib/groups/kinds-server'
import { kindName, kindOf, statusLabel } from '../../lib/library/model'
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
    <span class="rounded bg-medallion/25 px-1.5 py-0.5 eyebrow text-2xs">
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
  const [added, setAdded] = createSignal<Record<string, string>>({})
  const [busy, setBusy] = createSignal<string | null>(null)
  const [failed, setFailed] = createSignal<string | null>(null)

  async function add(card: MessageComponent) {
    setBusy(card.title.id)
    setFailed(null)
    try {
      const entry = await addTitleToLibrary({
        data: { titleId: card.title.id, type: card.title.type },
      })
      setAdded({
        ...added(),
        [card.title.id]: statusLabel(
          entry.status,
          kindOf(card.title.type, card.title.isAnime),
        ),
      })
    } catch {
      setFailed(card.title.id)
    } finally {
      setBusy(null)
    }
  }

  return (
    <ul class="mt-2 grid max-w-xl gap-2 sm:grid-cols-2">
      <For each={props.cards}>
        {(card) => {
          const kind = () => kindOf(card.title.type, card.title.isAnime)
          return (
            <li class="flex gap-3 rounded-xl border border-line bg-paper p-2">
              <Link
                to="/app/title/$id"
                params={{ id: card.title.id }}
                class="w-12 shrink-0"
              >
                <Poster url={card.title.posterUrl} kind={kind()} class="w-12" />
              </Link>
              <div class="flex min-w-0 flex-1 flex-col">
                <Link
                  to="/app/title/$id"
                  params={{ id: card.title.id }}
                  class="truncate text-sm font-semibold hover:underline"
                >
                  {card.title.title}
                </Link>
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
                  <Show
                    when={added()[card.title.id]}
                    fallback={
                      <Button
                        variant="outline"
                        size="xs"
                        disabled={busy() === card.title.id}
                        onClick={() => void add(card)}
                        class="px-2.5 py-0.5"
                      >
                        {failed() === card.title.id
                          ? 'Not added · Retry'
                          : 'Add to my library'}
                      </Button>
                    }
                  >
                    {(status) => (
                      <span class="rounded-full bg-accent/12 px-2.5 py-0.5 text-xs font-medium text-accent">
                        Added · {status()}
                      </span>
                    )}
                  </Show>
                </div>
              </div>
            </li>
          )
        }}
      </For>
    </ul>
  )
}
