import reedMark from '../assets/brand/reed-mark.webp'

// DESIGN.md "Brand": the reed mark is Aaru's quiet presence while it works, a slow breath and
// never a spinner. It says "working" only when something is: an import being read or matched.
// Still under reduced motion (the breath lives in a no-preference media query).
export function AgentPresence(props: { label: string; class?: string }) {
  return (
    <span
      role="status"
      class={`inline-flex items-center gap-2 text-sm text-muted ${props.class ?? ''}`}
    >
      <img
        src={reedMark}
        alt=""
        width="14"
        height="20"
        class="aaru-breathe h-5 w-auto"
        decoding="async"
      />
      {props.label}
    </span>
  )
}
