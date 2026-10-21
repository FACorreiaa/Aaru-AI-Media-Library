// Size budget for the client build. Reads TanStack Start's build manifest so every route is
// measured by what it actually loads first: the root's chunks plus the route's own preloads.
// Sizes are gzip -9 bytes. `npm run size` checks; `npm run size -- --update` re-seeds
// size-budget.json at 3% over the current build (only on purpose, with the reason in the PR).
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { gzipSync } from 'node:zlib'

const root = new URL('..', import.meta.url).pathname
const client = join(root, 'dist/client')
const serverAssets = join(root, 'dist/server/assets')
const budgetFile = join(root, 'size-budget.json')
const headroom = 1.03

const manifestFile = readdirSync(serverAssets).find((f) =>
  f.startsWith('_tanstack-start-manifest'),
)
if (!manifestFile) {
  console.error(
    'No TanStack Start manifest in dist/server/assets. Run `npm run build` first.',
  )
  process.exit(1)
}
const { tsrStartManifest } = await import(
  pathToFileURL(join(serverAssets, manifestFile)).href
)
const { routes } = tsrStartManifest()

const sizes = new Map()
const gz = (asset) => {
  if (!sizes.has(asset)) {
    sizes.set(
      asset,
      gzipSync(readFileSync(join(client, asset)), { level: 9 }).length,
    )
  }
  return sizes.get(asset)
}
const sum = (assets) =>
  [...assets].reduce((total, asset) => total + gz(asset), 0)

const rootRoute = routes.__root__
const shared = new Set([
  ...(rootRoute.preloads ?? []),
  ...(rootRoute.scripts ?? []).map((s) => s.attrs?.src).filter(Boolean),
])

const assets = readdirSync(join(client, 'assets'))
const measured = {
  totalJs: sum(
    assets.filter((f) => f.endsWith('.js')).map((f) => `/assets/${f}`),
  ),
  css: sum(assets.filter((f) => f.endsWith('.css')).map((f) => `/assets/${f}`)),
  shared: sum(shared),
  routes: Object.fromEntries(
    Object.entries(routes)
      .filter(([id]) => id !== '__root__')
      .map(([id, route]) => [
        id,
        sum(new Set([...shared, ...(route.preloads ?? [])])),
      ])
      .sort(([a], [b]) => a.localeCompare(b)),
  ),
}

if (process.argv.includes('--update')) {
  const seed = (n) => Math.ceil(n * headroom)
  const budget = {
    totalJs: seed(measured.totalJs),
    css: seed(measured.css),
    shared: seed(measured.shared),
    routes: Object.fromEntries(
      Object.entries(measured.routes).map(([id, n]) => [id, seed(n)]),
    ),
  }
  writeFileSync(budgetFile, `${JSON.stringify(budget, null, 2)}\n`)
  console.log(`Wrote ${budgetFile}`)
  process.exit(0)
}

const budget = JSON.parse(readFileSync(budgetFile, 'utf8'))
const kb = (n) => `${(n / 1024).toFixed(1)} KB`
const rows = [
  ['total JS', measured.totalJs, budget.totalJs],
  ['CSS', measured.css, budget.css],
  ['shared (every page)', measured.shared, budget.shared],
  ...Object.entries(measured.routes).map(([id, n]) => [
    `route ${id}`,
    n,
    budget.routes[id],
  ]),
]

let failed = false
for (const [name, actual, limit] of rows) {
  const over = limit === undefined || actual > limit
  if (over) failed = true
  const verdict =
    limit === undefined
      ? 'NO BUDGET (add it with --update)'
      : over
        ? 'OVER'
        : 'ok'
  console.log(
    `${name.padEnd(28)} ${kb(actual).padStart(9)} / ${limit === undefined ? '—' : kb(limit).padStart(9)}  ${verdict}`,
  )
}
if (failed) {
  console.error(
    '\nSize budget exceeded. Shrink it, or re-seed with --update and justify it in the PR.',
  )
  process.exit(1)
}
