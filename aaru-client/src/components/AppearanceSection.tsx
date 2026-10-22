import { useRouter } from '@tanstack/solid-router'
import { createSignal, onMount } from 'solid-js'
import { APPEARANCES, applyAppearance } from '../lib/appearance'
import type { Appearance } from '../lib/appearance'
import { readAppearance } from '../lib/appearance-read'
import { Segmented } from './Segmented'
import { SettingsSection } from './settings/SettingsSection'

// Account → On this device (DESIGN.md §18): light, dark or the system's, for this browser only.
// The change is drawn at once; the root loader then re-runs so the browser's theme-color and
// later pages agree.
export function AppearanceSection() {
  const router = useRouter()
  const [appearance, setAppearance] = createSignal<Appearance>('system')
  onMount(() => setAppearance(readAppearance()))

  function choose(value: Appearance) {
    setAppearance(value)
    applyAppearance(value)
    void router.invalidate()
  }

  return (
    <SettingsSection
      title="On this device"
      description="Appearance in this browser. Your other devices keep their own."
    >
      <Segmented
        label="Appearance"
        options={APPEARANCES}
        value={appearance()}
        onChange={choose}
        itemClass="min-h-9 px-4 text-sm"
      />
    </SettingsSection>
  )
}
