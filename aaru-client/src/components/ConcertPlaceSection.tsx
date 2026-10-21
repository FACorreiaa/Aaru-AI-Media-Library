import { Show, Suspense, createSignal, lazy } from 'solid-js'
import { placeLabel } from '../lib/concerts/place'
import type { ConcertPlaceSetting } from '../lib/concerts/model'
import { deleteConcertPlace } from '../lib/concerts/server'
import { Button } from './ui/button'
import { Card } from './ui/card'

// The picker loads on the first tap: Account is opened far more often than the city changes.
const CityPicker = lazy(() =>
  import('./CityPicker').then((m) => ({ default: m.CityPicker })),
)

/** Settings → Account: the city Discover's Concerts view starts from (MUS-003). */
export function ConcertPlaceSection(props: { setting: ConcertPlaceSetting }) {
  const [setting, setSetting] = createSignal(props.setting)
  const [picking, setPicking] = createSignal(false)
  const [removing, setRemoving] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function remove() {
    setRemoving(true)
    setProblem(null)
    try {
      await deleteConcertPlace()
      setSetting({ ...setting(), place: undefined })
    } catch (error) {
      setProblem(
        error instanceof Error ? error.message : 'That city was not removed.',
      )
    } finally {
      setRemoving(false)
    }
  }

  return (
    <Card class="mt-10 p-5">
      <h2 class="font-display text-xl font-medium">Concerts near</h2>
      <Show
        when={setting().place}
        fallback={
          <p class="mt-2 text-sm text-muted">
            No city yet. Concerts on Discover start from it when you don’t share
            your location.
          </p>
        }
      >
        {(place) => (
          <>
            <p class="mt-2 font-medium text-ink">{placeLabel(place())}</p>
            <p class="mt-1 text-sm text-muted">
              Concerts on Discover start from here. Saved to about a kilometre.
            </p>
          </>
        )}
      </Show>
      <div class="mt-4 flex flex-wrap gap-2">
        <Button size="sm" onClick={() => setPicking(true)}>
          {setting().place ? 'Change' : 'Choose a city'}
        </Button>
        <Show when={setting().place}>
          <Button
            variant="ghost"
            size="sm"
            disabled={removing()}
            onClick={() => void remove()}
          >
            {removing() ? 'Removing…' : 'Remove'}
          </Button>
        </Show>
      </div>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
      <Show when={picking()}>
        <Suspense>
          <CityPicker onSaved={setSetting} onClose={() => setPicking(false)} />
        </Suspense>
      </Show>
    </Card>
  )
}
