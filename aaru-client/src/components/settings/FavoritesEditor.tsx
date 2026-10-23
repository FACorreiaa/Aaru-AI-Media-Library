import { For, Show, createSignal } from 'solid-js'
import {
  Button,
  Dialog,
  DialogContent,
  DialogPortal,
  DialogTitle,
} from '~/components/ui'
import { hitRef } from '../../lib/groups/kinds'
import { kindOf } from '../../lib/library/model'
import type { CatalogHit } from '../../lib/library/model'
import {
  FAVORITE_KINDS,
  FAVORITE_LIMIT,
  favoriteLabel,
  favoriteRef,
  moveFavorite,
} from '../../lib/favorites/model'
import type { FavoriteKind, Favorites } from '../../lib/favorites/model'
import { saveFavorites } from '../../lib/favorites/server'
import { TitlePicker } from '../groups/TitlePicker'
import { Poster } from '../Poster'
import { Segmented } from '../Segmented'
import { SettingsSection } from './SettingsSection'

/**
 * FAV-001 in Settings → Account: a top 10 per kind, any title from the catalog. Each change
 * saves the whole kind at once, shown first and rolled back if the server says no.
 */
export function FavoritesEditor(props: { favorites: Favorites }) {
  const [favorites, setFavorites] = createSignal(props.favorites)
  const [kind, setKind] = createSignal<FavoriteKind>('film')
  const [adding, setAdding] = createSignal(false)
  const [busy, setBusy] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const titles = () => favorites()[kind()]
  const full = () => titles().length >= FAVORITE_LIMIT

  async function save(
    next: Favorites[FavoriteKind],
    refs = next.map(favoriteRef),
  ) {
    const before = favorites()
    const which = kind()
    setFavorites({ ...before, [which]: next })
    setProblem(null)
    setBusy(true)
    try {
      setFavorites(await saveFavorites({ data: { kind: which, items: refs } }))
    } catch (error) {
      setFavorites(before)
      setProblem(
        error instanceof Error
          ? error.message
          : 'Your favorites were not saved.',
      )
    } finally {
      setBusy(false)
    }
  }

  function add(hit: CatalogHit) {
    setAdding(false)
    const current = titles()
    // Shown once the server answers: a search hit has no Aaru id until it is resolved.
    void save(current, [...current.map(favoriteRef), hitRef(hit)])
  }

  return (
    <SettingsSection
      id="favorites"
      title="Favorites"
      description="Up to 10 per kind, first is your favorite. They show on your profile, and to friends while you share your library."
    >
      <Segmented
        label="Kind"
        variant="chip"
        options={FAVORITE_KINDS.map((k) => ({
          value: k,
          label: favoriteLabel(k),
        }))}
        value={kind()}
        onChange={(next) => {
          setProblem(null)
          setKind(next)
        }}
        itemClass="min-h-8 px-3 text-sm"
      />
      <Show when={problem()}>
        {(text) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {text()}
          </p>
        )}
      </Show>
      <Show
        when={titles().length > 0}
        fallback={
          <p class="mt-4 text-sm text-muted">
            No favorite {favoriteLabel(kind()).toLowerCase()} yet.
          </p>
        }
      >
        <ol class="mt-4 flex flex-col gap-2" aria-busy={busy()}>
          <For each={titles()}>
            {(title, index) => (
              <li class="flex items-center gap-3">
                <span class="w-5 text-right text-sm text-muted tabular-nums">
                  {index() + 1}
                </span>
                <Poster
                  url={title.posterUrl}
                  kind={kindOf(title.type, title.isAnime)}
                  class="w-9 shrink-0"
                />
                <span class="min-w-0 flex-1 truncate font-medium">
                  {title.title}
                </span>
                <Button
                  variant="soft"
                  size="bare"
                  aria-label={`Move ${title.title} up`}
                  disabled={busy() || index() === 0}
                  class="px-2 py-1"
                  onClick={() => void save(moveFavorite(titles(), index(), -1))}
                >
                  ↑
                </Button>
                <Button
                  variant="soft"
                  size="bare"
                  aria-label={`Move ${title.title} down`}
                  disabled={busy() || index() === titles().length - 1}
                  class="px-2 py-1"
                  onClick={() => void save(moveFavorite(titles(), index(), 1))}
                >
                  ↓
                </Button>
                <Button
                  variant="ghost"
                  size="bare"
                  disabled={busy()}
                  class="min-h-9 px-1.5 text-sm hover:text-danger"
                  onClick={() =>
                    void save(titles().filter((t) => t.id !== title.id))
                  }
                >
                  Remove
                </Button>
              </li>
            )}
          </For>
        </ol>
      </Show>
      <Button
        variant="outline"
        class="mt-4"
        disabled={busy() || full()}
        onClick={() => setAdding(true)}
      >
        {full()
          ? 'Top 10 is full'
          : `Add ${favoriteLabel(kind()).toLowerCase()}`}
      </Button>

      <Dialog open={adding()} onOpenChange={setAdding}>
        <DialogPortal>
          <DialogContent
            placement="sheet"
            class="block w-[min(28rem,calc(100vw-2rem))] gap-0 p-5 sm:max-w-none"
          >
            <DialogTitle class="mb-3 text-2xl">
              Add to your {favoriteLabel(kind()).toLowerCase()}
            </DialogTitle>
            <TitlePicker
              kinds={[kind()]}
              initialKind={kind()}
              busy={busy()}
              onPick={add}
            />
          </DialogContent>
        </DialogPortal>
      </Dialog>
    </SettingsSection>
  )
}
