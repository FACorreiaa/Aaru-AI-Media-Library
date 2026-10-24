import { Link } from '@tanstack/solid-router'
import { Show } from 'solid-js'
import { KINDS, kindOf } from '../lib/library/model'
import type { CatalogHit, LibraryStatus } from '../lib/library/model'
import { previewParams } from '../lib/title/preview'
import { AddControl } from './AddControl'
import { Poster } from './Poster'
import {
  Button,
  buttonVariants,
  Dialog,
  DialogContent,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'

/**
 * A public card the user does not have yet (Discover, Seasons, On air): what the card already
 * knows, in one place, with Add. "All details" opens the title's catalog page (LIB-006); once
 * added, it links to the Title room.
 */
export function CatalogPreviewDialog(props: {
  hit: CatalogHit
  /** The library item once added, from the hit or from an add made here. */
  libraryItemId?: string
  adding: boolean
  onAdd: (status: LibraryStatus) => void
  onList: () => void
  onClose: () => void
}) {
  const h = () => props.hit
  const kind = () => kindOf(h().type, h().isAnime)
  const meta = () =>
    [KINDS.find((k) => k.kind === kind())?.label, h().year, h().byline]
      .filter(Boolean)
      .join(' · ')
  return (
    <Dialog
      open
      onOpenChange={(next) => {
        if (!next) props.onClose()
      }}
    >
      <DialogPortal>
        <DialogContent class="block w-[min(32rem,calc(100vw-2rem))] p-5">
          <div class="flex gap-4">
            <Poster url={h().posterUrl} kind={kind()} class="w-28 shrink-0" />
            <div class="min-w-0 pr-8">
              <DialogTitle class="font-display text-2xl leading-tight font-medium">
                {h().title}
              </DialogTitle>
              <Show when={h().originalTitle && h().originalTitle !== h().title}>
                <p class="mt-1 text-sm text-muted">{h().originalTitle}</p>
              </Show>
              <Show when={meta()}>
                <p class="mt-1 text-sm text-muted">{meta()}</p>
              </Show>
            </div>
          </div>
          <Show when={h().overview}>
            {(overview) => (
              <p class="mt-4 max-h-48 overflow-y-auto text-sm leading-relaxed">
                {overview()}
              </p>
            )}
          </Show>
          <div class="mt-5 flex flex-wrap items-center gap-2">
            <Show
              when={props.libraryItemId}
              fallback={
                <>
                  <AddControl
                    hit={h()}
                    adding={props.adding}
                    onAdd={props.onAdd}
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => props.onList()}
                  >
                    List…
                  </Button>
                  <Show when={previewParams(h())}>
                    {(params) => (
                      <Link
                        to="/app/catalog/$type/$provider/$ref"
                        params={params()}
                        class={buttonVariants({
                          variant: 'outline',
                          size: 'sm',
                        })}
                        onClick={() => props.onClose()}
                      >
                        All details
                      </Link>
                    )}
                  </Show>
                </>
              }
            >
              {(id) => (
                <>
                  <p class="text-sm font-medium text-accent">In your library</p>
                  <Link
                    to="/app/title/$id"
                    params={{ id: id() }}
                    class={buttonVariants({ variant: 'outline', size: 'sm' })}
                  >
                    Open
                  </Link>
                </>
              )}
            </Show>
          </div>
        </DialogContent>
      </DialogPortal>
    </Dialog>
  )
}
