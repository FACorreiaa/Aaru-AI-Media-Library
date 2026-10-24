/** A round monogram: groups in the rail, people in rows. */
export function Monogram(props: {
  text: string
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
    <span
      aria-hidden="true"
      class={`grid shrink-0 place-items-center rounded-full bg-medallion/20 font-display font-medium ${size()} ${props.class ?? ''}`}
    >
      {props.text}
    </span>
  )
}
