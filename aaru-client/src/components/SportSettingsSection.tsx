import { Show, createSignal, onMount } from 'solid-js'
import {
  Button,
  Select,
  SelectContent,
  SelectItem,
  SelectPortal,
  SelectTrigger,
  SelectValue,
} from '~/components/ui'
import { countries, countryName, regionOf } from '../lib/sports/countries'
import type { Country } from '../lib/sports/countries'
import type { SportSettings } from '../lib/sports/model'
import { saveSportSettings } from '../lib/sports/server'
import { SettingsSection } from './settings/SettingsSection'

/**
 * Settings → Sports (SPT-003): the one country "Where to watch" looks at. The browser's region
 * is offered as a suggestion, and nothing is saved until the user picks.
 */
export function SportSettingsSection(props: { setting: SportSettings }) {
  const [code, setCode] = createSignal(props.setting.watchCountryCode ?? null)
  const [suggested, setSuggested] = createSignal<string | null>(null)
  const [saving, setSaving] = createSignal(false)
  const [problem, setProblem] = createSignal<string | null>(null)
  const options = countries()
  const selected = () => options.find((c) => c.code === code()) ?? null

  // Only the browser knows its language.
  onMount(() => setSuggested(regionOf(navigator.language)))

  async function save(next: string | null) {
    if (next === code()) return
    const before = code()
    setCode(next)
    setSaving(true)
    setProblem(null)
    try {
      const saved = await saveSportSettings({
        data: { watchCountryCode: next },
      })
      setCode(saved.watchCountryCode ?? null)
    } catch (error) {
      setCode(before)
      setProblem(
        error instanceof Error ? error.message : 'That country was not saved.',
      )
    } finally {
      setSaving(false)
    }
  }

  return (
    <SettingsSection
      id="sports"
      title="Sports"
      description="Where to watch shows the channels in this country first."
    >
      <h3 class="text-sm font-semibold" id="sports-country-label">
        Where to watch
      </h3>
      <div class="mt-2 flex flex-wrap items-center gap-2">
        <Select<Country>
          aria-labelledby="sports-country-label"
          options={options}
          optionValue="code"
          optionTextValue="name"
          value={selected()}
          placeholder="Choose a country"
          disabled={saving()}
          onChange={(choice) => {
            if (choice) void save(choice.code)
          }}
          itemComponent={(p) => (
            <SelectItem item={p.item}>{p.item.rawValue.name}</SelectItem>
          )}
        >
          <SelectTrigger class="h-auto min-w-56 rounded-full border-line py-1.5 pr-3 pl-4 font-medium shadow-none">
            <SelectValue<Country>>
              {(state) => state.selectedOption().name}
            </SelectValue>
          </SelectTrigger>
          <SelectPortal>
            <SelectContent class="max-h-80 overflow-y-auto rounded-panel border-line bg-paper" />
          </SelectPortal>
        </Select>
        <Show when={code()}>
          <Button
            variant="ghost"
            size="sm"
            disabled={saving()}
            onClick={() => void save(null)}
          >
            Clear
          </Button>
        </Show>
      </div>
      <Show when={!code() && suggested()}>
        {(region) => (
          <p class="mt-3 text-sm text-muted">
            Your browser says {countryName(region())}.{' '}
            <Button
              variant="link"
              size="bare"
              class="font-medium text-accent"
              disabled={saving()}
              onClick={() => void save(region())}
            >
              Use {countryName(region())}
            </Button>
          </p>
        )}
      </Show>
      <Show when={!code() && !suggested()}>
        <p class="mt-3 text-sm text-muted">
          No country yet: an event lists every channel by country.
        </p>
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </SettingsSection>
  )
}
