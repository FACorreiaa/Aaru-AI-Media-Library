import { useRouter } from '@tanstack/solid-router'
import { For, createSignal, onMount } from 'solid-js'
import { APPEARANCES, applyAppearance } from '../lib/appearance'
import type { Appearance } from '../lib/appearance'
import { readAppearance } from '../lib/appearance-read'
import { Card } from './ui/card'
import { SegmentedControl, SegmentedControlItem } from './ui/segmented-control'

// Light, dark or the system's, for this browser only. The change is drawn at once; the root
// loader then re-runs so the browser's theme-color and later pages agree.
export function AppearanceSection() {
  const router = useRouter()
  const [appearance, setAppearance] = createSignal<Appearance>('system')
  onMount(() => setAppearance(readAppearance()))

  function choose(next: string) {
    const value = next as Appearance
    setAppearance(value)
    applyAppearance(value)
    void router.invalidate()
  }

  return (
    <Card class="mt-10 p-5">
      <h2 class="font-display text-xl font-medium">Appearance</h2>
      <p class="mt-1 text-sm text-muted">
        On this browser. System follows your device's light and dark.
      </p>
      <SegmentedControl
        class="mt-4 inline-flex rounded-full border border-line p-1"
        aria-label="Appearance"
        value={appearance()}
        onChange={choose}
      >
        <For each={APPEARANCES}>
          {(option) => (
            <SegmentedControlItem
              value={option.value}
              class="min-h-9 px-4 text-sm"
            >
              {option.label}
            </SegmentedControlItem>
          )}
        </For>
      </SegmentedControl>
    </Card>
  )
}
