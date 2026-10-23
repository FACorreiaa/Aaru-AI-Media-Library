import { Show, createSignal } from 'solid-js'
import { Button } from '~/components/ui'
import { addTitleToLibrary } from '../lib/groups/kinds-server'
import { kindOf, statusLabel } from '../lib/library/model'
import type { MediaType } from '../lib/media'

/**
 * "Add to my library" for a title someone else put in front of you: an Aaru reply's card
 * (GRP-011) or a friend's post (BOARD-002). The reader's own tap, the same journaled add as
 * anywhere else; adding a title you already have changes nothing and says where it is.
 * `card` is the outlined button on a title card; `inline` reads as part of a title line.
 */
export function AddToLibrary(props: {
  title: { id: string; type: MediaType; isAnime: boolean }
  look?: 'card' | 'inline'
}) {
  const [added, setAdded] = createSignal<string | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [failed, setFailed] = createSignal(false)
  const inline = () => props.look === 'inline'

  async function add() {
    setBusy(true)
    setFailed(false)
    try {
      const entry = await addTitleToLibrary({
        data: { titleId: props.title.id, type: props.title.type },
      })
      setAdded(
        statusLabel(
          entry.status,
          kindOf(props.title.type, props.title.isAnime),
        ),
      )
    } catch {
      setFailed(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Show
      when={added()}
      fallback={
        <Button
          variant={inline() ? 'ghost' : 'outline'}
          size={inline() ? 'bare' : 'xs'}
          disabled={busy()}
          onClick={() => void add()}
          class={
            inline()
              ? 'text-xs font-medium text-accent hover:text-accent hover:underline'
              : 'px-2.5 py-0.5'
          }
        >
          {failed() ? 'Not added · Retry' : 'Add to my library'}
        </Button>
      }
    >
      {(status) => (
        <span
          class={
            inline()
              ? 'text-xs text-muted'
              : 'rounded-full bg-accent/12 px-2.5 py-0.5 text-xs font-medium text-accent'
          }
        >
          Added · {status()}
        </span>
      )}
    </Show>
  )
}
