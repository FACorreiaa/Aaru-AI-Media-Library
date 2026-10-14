import { defineConfig } from 'vitest/config'

// Unit tests run in Node without the Workers runtime; they cover pure modules only.
export default defineConfig({
  test: { include: ['src/**/*.test.ts'], environment: 'node' },
})
