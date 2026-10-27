import { Show } from 'solid-js'
import { avatarSrc } from '../../lib/profile/avatar-src'
import { Avatar, AvatarFallback, AvatarImage } from '~/components/ui'

/** A round monogram: groups in the rail, people in rows. A person with a photo shows it
 * (SOC-001b), the monogram staying underneath until it loads. */
export function Monogram(props: {
  text: string
  avatarUrl?: string | null
  size?: 'sm' | 'md' | 'lg'
  class?: string
}) {
  const size = () =>
    props.size === 'lg'
      ? 'size-12 text-base'
      : props.size === 'sm'
        ? 'size-8 text-xs'
        : 'size-10 text-sm'
  return (
    <Avatar
      aria-hidden="true"
      class={`bg-medallion/20 font-display font-medium ${size()} ${props.class ?? ''}`}
    >
      <Show when={avatarSrc(props.avatarUrl)}>
        {(src) => <AvatarImage src={src()} alt="" />}
      </Show>
      <AvatarFallback>{props.text}</AvatarFallback>
    </Avatar>
  )
}
