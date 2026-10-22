import { defineConfig } from 'wxt'

// SCR-007: Aaru's browser extension, one Manifest V3 source for Chrome and Firefox. It reads the
// player page on three streaming sites and YouTube's watch page (SCR-009), and scrobbles to Aaru;
// it asks for nothing else. The sites' match list is the content script's (src/sites/index.ts).
export default defineConfig({
  srcDir: 'src',
  manifest: ({ browser, mode }) => ({
    name: 'Aaru',
    description:
      'Marks what you finish on Netflix, Disney+ and Prime Video as watched in Aaru, and shows your YouTube video as playing.',
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
              // Error reports (src/lib/reporting) are technical data. Mozilla lets that
              // category only be optional: Firefox shows it at install as an opt-in, and the
              // background sends nothing unless it was granted (reportingAllowed).
              data_collection_permissions: {
                required: ['none'],
                optional: ['technicalAndInteraction'],
              },
            },
          },
        }
      : {}),
  }),
})
