import { onMount } from 'solid-js'
import { Toaster as Sonner, toast } from 'somoto'
import { toasterReady } from './toast-bridge'

// Aaru: loaded on the first `toast()` (sonner.tsx), so somoto stays out of first loads.
// No Kobalte ColorModeProvider (the appearance is Aaru's own, lib/appearance.ts), so
// the theme follows the system and the colours below come from Aaru's tokens, which already
// follow a pinned appearance. Toasts are ink on paper's opposite; errors are the danger fill.
export default function ToasterView(props: Parameters<typeof Sonner>[0]) {
  // somoto drops toasts published before it subscribes, so the queue waits for this.
  onMount(() => toasterReady(toast))
  return (
    <Sonner
      theme="system"
      position="bottom-center"
      richColors
      icons={{
        success: (
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4"
            viewBox="0 0 24 24"
          >
            <g
              fill="none"
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
            >
              <circle cx="12" cy="12" r="10" />
              <path d="m9 12l2 2l4-4" />
            </g>
          </svg>
        ),
        info: (
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4"
            viewBox="0 0 24 24"
          >
            <g
              fill="none"
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
            >
              <circle cx="12" cy="12" r="10" />
              <path d="M12 16v-4m0-4h.01" />
            </g>
          </svg>
        ),
        warning: (
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4"
            viewBox="0 0 24 24"
          >
            <path
              fill="none"
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="m21.73 18l-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3M12 9v4m0 4h.01"
            />
          </svg>
        ),
        error: (
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4"
            viewBox="0 0 24 24"
          >
            <path
              fill="none"
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="m15 9l-6 6m-6.414 1.726A2 2 0 0 1 2 15.312V8.688a2 2 0 0 1 .586-1.414l4.688-4.688A2 2 0 0 1 8.688 2h6.624a2 2 0 0 1 1.414.586l4.688 4.688A2 2 0 0 1 22 8.688v6.624a2 2 0 0 1-.586 1.414l-4.688 4.688a2 2 0 0 1-1.414.586H8.688a2 2 0 0 1-1.414-.586zM9 9l6 6"
            />
          </svg>
        ),
        loading: (
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-4 animate-spin"
            viewBox="0 0 24 24"
          >
            <path
              fill="none"
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 2v4m4.2 1.8l2.9-2.9M18 12h4m-5.8 4.2l2.9 2.9M12 18v4m-7.1-2.9l2.9-2.9M2 12h4M4.9 4.9l2.9 2.9"
            />
          </svg>
        ),
      }}
      style={{
        '--normal-bg': 'var(--ink)',
        '--normal-text': 'var(--paper)',
        '--normal-border': 'transparent',
        '--error-bg': 'var(--danger)',
        '--error-text': 'var(--on-accent)',
        '--error-border': 'transparent',
        '--border-radius': 'var(--radius-panel)',
      }}
      {...props}
    />
  )
}
