import { For, Match, Switch, createSignal, onCleanup } from 'solid-js'
import { placeLabel, placeQuery } from '../lib/concerts/place'
import type { ConcertPlace, ConcertPlaceSetting } from '../lib/concerts/model'
import { saveConcertPlace, searchConcertPlaces } from '../lib/concerts/server'
import { Button } from './ui/button'
import { Dialog } from './ui/dialog'

const DEBOUNCE_MS = 300

/**
 * MUS-003's "Concerts near" picker: type a city, pick one of the matches, and it is saved as the
 * account's concerts city (shared with the Apple apps). Exists only while open.
 */
export function CityPicker(props: {
  onSaved: (setting: ConcertPlaceSetting) => void
  onClose: () => void
}) {
  let dialog: HTMLDialogElement | undefined
  const [text, setText] = createSignal('')
  const [places, setPlaces] = createSignal<ConcertPlace[] | null>(null)
  const [searching, setSearching] = createSignal(false)
  const [saving, setSaving] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)
  let timer: ReturnType<typeof setTimeout> | undefined
  let latest = 0

  onCleanup(() => clearTimeout(timer))

  function type(value: string) {
    setText(value)
    clearTimeout(timer)
    const query = placeQuery(value)
    const request = ++latest
    if (!query) {
      setPlaces(null)
      setSearching(false)
      return
    }
    setSearching(true)
    timer = setTimeout(() => void search(query, request), DEBOUNCE_MS)
  }

  async function search(query: string, request: number) {
    setProblem(null)
    try {
      const found = await searchConcertPlaces({ data: { q: query } })
      if (request === latest) setPlaces(found)
    } catch (error) {
      if (request === latest)
        setProblem(
          error instanceof Error
            ? error.message
            : 'Cities could not be searched right now.',
        )
    } finally {
      if (request === latest) setSearching(false)
    }
  }

  async function choose(place: ConcertPlace) {
    const key = placeKey(place)
    if (saving()) return
    setSaving(key)
    setProblem(null)
    try {
      props.onSaved(await saveConcertPlace({ data: place }))
      dialog?.close()
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That city was not saved.',
      )
    } finally {
      setSaving(null)
    }
  }

  return (
    <Dialog
      ref={dialog}
      openOnMount
      placement="sheet"
      aria-labelledby="city-picker-title"
      class="sm:max-w-md"
      onClose={() => props.onClose()}
    >
      <div class="flex items-center justify-between gap-4 border-b border-line px-5 py-4">
        <h2 id="city-picker-title" class="font-display text-xl font-medium">
          Concerts near
        </h2>
        <Button
          variant="ghost"
          size="bare"
          class="text-sm"
          onClick={() => dialog?.close()}
        >
          Cancel
        </Button>
      </div>
      <div class="px-5 pt-4">
        <label for="city-search" class="sr-only">
          City
        </label>
        <input
          id="city-search"
          type="search"
          autofocus
          autocomplete="off"
          spellcheck={false}
          placeholder="Search for a city"
          maxlength={100}
          value={text()}
          onInput={(e) => type(e.currentTarget.value)}
          class="min-h-11 w-full rounded-full border-0 bg-surface px-4 text-sm placeholder:text-muted focus:ring-2 focus:ring-accent"
        />
      </div>
      <div
        class="min-h-40 px-3 py-3"
        aria-live="polite"
        aria-busy={searching()}
      >
        <Switch>
          <Match when={problem()}>
            {(message) => (
              <p role="alert" class="px-2 py-3 text-sm text-danger">
                {message()}
              </p>
            )}
          </Match>
          <Match when={places() === null && !searching()}>
            <p class="px-2 py-3 text-sm text-muted">
              Concerts on Discover start from this city when you don’t share
              your location.
            </p>
          </Match>
          <Match when={places() === null || (searching() && !places()?.length)}>
            <p class="px-2 py-3 text-sm text-muted">Searching…</p>
          </Match>
          <Match when={places()?.length === 0}>
            <p class="px-2 py-3 text-sm text-muted">
              No city by that name. Try its spelling in the local language.
            </p>
          </Match>
          <Match when={places()}>
            {(found) => (
              <ul>
                <For each={found()}>
                  {(place) => (
                    <li>
                      <button
                        type="button"
                        class="flex w-full items-center justify-between gap-3 rounded-[12px] px-3 py-2.5 text-left transition-colors hover:bg-surface disabled:opacity-60 disabled:hover:bg-transparent"
                        disabled={saving() !== null}
                        onClick={() => void choose(place)}
                      >
                        <span class="min-w-0 truncate">
                          <span class="font-medium text-ink">{place.name}</span>
                          <span class="text-muted">
                            {placeLabel(place).slice(place.name.trim().length)}
                          </span>
                        </span>
                        <span class="shrink-0 text-sm text-muted">
                          {saving() === placeKey(place) ? 'Saving…' : ''}
                        </span>
                      </button>
                    </li>
                  )}
                </For>
              </ul>
            )}
          </Match>
        </Switch>
      </div>
    </Dialog>
  )
}

const placeKey = (place: ConcertPlace) =>
  `${place.latitude},${place.longitude},${place.name}`
