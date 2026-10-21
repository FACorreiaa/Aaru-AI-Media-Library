import { Show, createSignal } from 'solid-js'
import { kindGlyph } from '../../lib/groups/kinds'
import type { Channel } from '../../lib/groups/server'

/** What sits before a channel's name: `#`, ▶ or ▤, or a title channel's tiny poster (square for
 * an album). */
export function ChannelGlyph(props: { channel: Channel; class?: string }) {
  const [failed, setFailed] = createSignal(false)
  return (
    <Show
      when={
        props.channel.kind === 'title' &&
        props.channel.title?.posterUrl &&
        !failed()
      }
      fallback={
        <span
          aria-hidden="true"
          class={`w-4 shrink-0 text-center text-muted ${props.class ?? ''}`}
        >
          {kindGlyph(props.channel.kind)}
        </span>
      }
    >
      <img
        src={props.channel.title?.posterUrl}
        alt=""
        aria-hidden="true"
        loading="lazy"
        onError={() => setFailed(true)}
        class={`w-4 shrink-0 rounded-[3px] object-cover ${props.channel.title?.type === 'album' ? 'h-4' : 'h-5'} ${props.class ?? ''}`}
      />
    </Show>
  )
}
