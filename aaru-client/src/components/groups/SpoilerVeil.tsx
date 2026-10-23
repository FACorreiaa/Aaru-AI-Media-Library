import { Button } from '~/components/ui'

/**
 * SpoilerVeil (GRP-007): a group message that may spoil what the reader has not watched yet,
 * folded until they ask. Lifting it is local; nobody is told.
 */
export function SpoilerVeil(props: { onShow: () => void }) {
  return (
    <p class="mt-0.5 flex items-center gap-2 rounded-lg bg-surface px-3 py-1.5 text-sm text-muted">
      <span aria-hidden="true">◐</span>
      <span>May spoil what you haven't watched yet ·</span>
      <Button
        variant="link"
        size="bare"
        onClick={() => props.onShow()}
        class="font-medium text-accent"
      >
        Show
      </Button>
    </p>
  )
}
