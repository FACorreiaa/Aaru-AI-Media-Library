import { configDefaults, defineConfig } from 'vitest/config'

// Unit tests run in Node without the Workers runtime; they cover pure modules only.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
    // Pull requests run `vitest run --changed` (ci-web.yml): only the tests that import a
    // changed file. A change to one of these reruns everything, on top of the defaults
    // (package.json and this config). CI's own files are in the list because a change to
    // how the tests run should run them all.
    forceRerunTriggers: [
      ...configDefaults.forceRerunTriggers,
      '**/package-lock.json',
      '**/tsconfig.json',
      '**/.github/workflows/ci-web.yml',
      '**/.github/actions/npm-setup/**',
    ],
  },
})
