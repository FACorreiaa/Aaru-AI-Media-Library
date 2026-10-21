import { defineConfig } from 'wxt'

// SCR-007: Aaru's browser extension, one Manifest V3 source for Chrome and Firefox. It reads the
// player page on three streaming sites and scrobbles to Aaru; it asks for nothing else.
export default defineConfig({
  srcDir: 'src',
  manifest: ({ browser, mode }) => ({
    name: 'Aaru',
    description:
      'Marks what you finish on Netflix, Disney+ and Prime Video as watched in your Aaru library.',
    permissions: ['storage', 'alarms'],
    host_permissions: [
      'https://api.aaruapp.com/*',
      ...(mode === 'development' ? ['http://localhost/*'] : []),
    ],
    action: { default_title: 'Aaru' },
    ...(browser === 'firefox'
      ? {
          browser_specific_settings: {
            gecko: {
              id: 'extension@aaruapp.com',
              strict_min_version: '142.0',
              data_collection_permissions: { required: ['none'] },
            },
          },
        }
      : {}),
  }),
})
