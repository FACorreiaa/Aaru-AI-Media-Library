import type { components } from '../api/schema'
import type { ListRow } from './model'

// GRAPH-003 on the web: a list the owl planned in steps, read as the server keeps it. Inside a step
// the list's own order decides; a member no step names was added by hand and is shown last.

export type ListRoadmap = components['schemas']['ListRoadmap']

export interface RoadmapEntry {
  row: ListRow
  note?: string
  optional: boolean
  /** Set on titles read side by side; the same number for each of them. */
  pair?: number
}

export interface RoadmapSection {
  heading: string
  note?: string
  missing: string[]
  entries: RoadmapEntry[]
}

export const ADDED_BY_HAND = 'Added by hand'

export function roadmapSections(
  roadmap: ListRoadmap,
  rows: ListRow[],
): RoadmapSection[] {
  const position = new Map(rows.map((r, i) => [r.titleId, i]))
  const byId = new Map(rows.map((r) => [r.titleId, r]))
  const placed = new Set<string>()
  const key = (id: string) => id.toLowerCase()
  const sections: RoadmapSection[] = roadmap.steps.map((step) => {
    const entries: RoadmapEntry[] = []
    for (const item of step.items) {
      const row = byId.get(item.titleId) ?? findRow(rows, item.titleId)
      if (!row || placed.has(key(row.titleId))) continue
      placed.add(key(row.titleId))
      entries.push({
        row,
        note: item.note,
        optional: item.optional ?? false,
        pair: item.pair,
      })
    }
    entries.sort(
      (a, b) =>
        (position.get(a.row.titleId) ?? 0) - (position.get(b.row.titleId) ?? 0),
    )
    return {
      heading: step.heading,
      note: step.note,
      missing: step.missing ?? [],
      entries,
    }
  })
  const loose = rows.filter((r) => !placed.has(key(r.titleId)))
  if (loose.length > 0)
    sections.push({
      heading: ADDED_BY_HAND,
      missing: [],
      entries: loose.map((row) => ({ row, optional: false })),
    })
  return sections.filter((s) => s.entries.length > 0 || s.missing.length > 0)
}

/** Ids are upper-case on the wire; a row's may not be. */
function findRow(rows: ListRow[], id: string): ListRow | undefined {
  const wanted = id.toLowerCase()
  return rows.find((r) => r.titleId.toLowerCase() === wanted)
}
