import { Show, Suspense, createSignal, lazy } from 'solid-js'
import { placeLabel } from '../lib/concerts/place'
import { lastShown } from '../lib/presence'
import type { ConcertPlaceSetting } from '../lib/concerts/model'
import { deleteConcertPlace } from '../lib/concerts/server'
import { Button } from '~/components/ui'
import { SettingsSection } from './settings/SettingsSection'

// The picker loads on the first tap: Account is opened far more often than the city changes.
const CityPicker = lazy(() =>
  import('./CityPicker').then((m) => ({ default: m.CityPicker })),
)

/** Friends & privacy → Location (DESIGN.md §18): the city Discover's Concerts view starts
 * from (MUS-003), the one place Aaru stores where you are. */
export function ConcertPlaceSection(props: { setting: ConcertPlaceSetting }) {
  const [setting, setSetting] = createSignal(props.setting)
  const [picking, setPicking] = createSignal(false)
  const picked = lastShown(() => (picking() ? true : null))
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
    <SettingsSection
      id="location"
      title="Location"
      description="The only place Aaru keeps where you are, and only while concerts are on."
    >
      <h3 class="text-sm font-semibold">Concerts near</h3>
      <Show
        when={setting().place}
        fallback={
          <p class="mt-1 text-sm text-muted">
            No city yet. Concerts on Discover start from it when you don’t share
            your location.
          </p>
        }
      >
        {(place) => (
          <>
            <p class="mt-1 font-medium text-ink">{placeLabel(place())}</p>
            <p class="mt-1 text-sm text-muted">
              Concerts on Discover start from here. Saved to about a kilometre.
            </p>
          </>
        )}
      </Show>
      <div class="mt-4 flex flex-wrap gap-2">
        <Button variant="outline" size="sm" onClick={() => setPicking(true)}>
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
      {/* Mounted from the first tap on, so closing plays the exit (WEB-011). */}
      <Show when={picked()}>
        <Suspense>
          <CityPicker
            open={picking()}
            onSaved={setSetting}
            onClose={() => setPicking(false)}
          />
        </Suspense>
      </Show>
    </SettingsSection>
  )
}
