import type { components } from '../api/schema'
import { KINDS, statusLabel } from '../library/model'
import type { MediaKind } from '../library/model'

// GRAPH-007: a World, one story universe across every kind, as the server built and laid it out.
// The server chooses every title, lane and place; the web only draws it. Catalog data and the
// viewer's own marks: nothing here is a recommendation.

export type World = components['schemas']['World']
export type WorldLane = components['schemas']['WorldLane']
export type WorldTitle = components['schemas']['WorldTitle']
export type WorldLaneKind = components['schemas']['WorldLaneKind']
export type WorldSummary = components['schemas']['WorldSummary']

/** A lane's kind is a media kind by the same name. */
export function laneKind(lane: WorldLaneKind): MediaKind {
  return lane
}

const kindLabel = (lane: WorldLaneKind): string =>
  KINDS.find((k) => k.kind === laneKind(lane))?.label ?? lane

/** "Books" for a lane's heading. */
export function laneLabel(lane: WorldLaneKind): string {
  return kindLabel(lane)
}

/** "5 of 11". */
export function countLabel(finished: number, total: number): string {
  return `${finished} of ${total}`
}

/** "Books, Films and Shows". */
export function kindsLabel(kinds: WorldLaneKind[]): string {
  return new Intl.ListFormat('en', { type: 'conjunction' }).format(
    kinds.map(kindLabel),
  )
}

/** How far along, from 0 to 1; 0 for an empty World. */
export function progressShare(finished: number, total: number): number {
  return total > 0 ? Math.min(1, finished / total) : 0
}

/** True when there is a map to draw: a built World of two titles or more. */
export function isReady(world: World | null | undefined): world is World {
  return !!world && world.state === 'ready' && world.total >= 2
}

/** How many titles the viewer does not have: what "Add the rest" would plan. */
export function missingCount(world: World): number {
  return world.lanes
    .flatMap((lane) => lane.titles)
    .filter((title) => !title.libraryItemId).length
}

/** The year a title came out, when the catalog knows. */
export function titleYear(title: WorldTitle): string | undefined {
  return title.releaseDate?.slice(0, 4) ?? title.ref.year?.toString()
}

/** What a screen reader hears for one title: its name, year, and where the viewer stands. */
export function titleLabel(
  title: WorldTitle,
  lane: WorldLaneKind,
  startHere: boolean,
): string {
  const parts = [title.ref.title ?? 'Untitled']
  const year = titleYear(title)
  if (year) parts.push(year)
  if (title.side) parts.push('side story')
  parts.push(
    title.status
      ? statusLabel(title.status, laneKind(lane))
      : 'not in your library',
  )
  if (startHere) parts.push('start here')
  else if (title.next) parts.push('next in this lane')
  return parts.join(', ')
}

/** One lane's own count, for its heading and the share image. */
export function laneCount(lane: WorldLane): {
  finished: number
  total: number
} {
  return {
    finished: lane.titles.filter((t) => t.status === 'finished').length,
    total: lane.titles.length,
  }
}

// MARK: Layout

/** Where a World's tiles and lines go: a row per lane, a column per place in it. A lane's rail
 * runs through the middle of its posters; a link between lanes is a rung that drops from under
 * the upper title to just above the lower lane's label. The same numbers as the Apple app's
 * `WorldLayout`. */
export const WORLD = {
  tileWidth: 72,
  posterHeight: 108,
  column: 96,
  labelHeight: 28,
  captionHeight: 56,
  laneGap: 32,
  pad: 16,
} as const

export const WORLD_ROW =
  WORLD.labelHeight + WORLD.posterHeight + WORLD.captionHeight + WORLD.laneGap

export type WorldPlace = { lane: number; column: number }

export type WorldLayout = {
  width: number
  height: number
  /** Each title's lane and place, by key. */
  place: Map<string, WorldPlace>
  /** Links that cross lanes, upper lane first. Links inside a lane are its rail. */
  rungs: Array<{ upper: WorldPlace; lower: WorldPlace }>
}

export function worldLayout(world: World): WorldLayout {
  const place = new Map<string, WorldPlace>()
  world.lanes.forEach((lane, laneIndex) =>
    lane.titles.forEach((title, column) => {
      if (!place.has(title.key))
        place.set(title.key, { lane: laneIndex, column })
    }),
  )
  const longest = Math.max(0, ...world.lanes.map((lane) => lane.titles.length))
  const rungs: WorldLayout['rungs'] = []
  for (const link of world.links) {
    const one = place.get(link.from)
    const other = place.get(link.to)
    if (!one || !other || one.lane === other.lane) continue
    rungs.push(
      one.lane < other.lane
        ? { upper: one, lower: other }
        : { upper: other, lower: one },
    )
  }
  return {
    width:
      WORLD.pad * 2 + Math.max(longest - 1, 0) * WORLD.column + WORLD.tileWidth,
    height: WORLD.pad + world.lanes.length * WORLD_ROW,
    place,
    rungs,
  }
}

/** The top-left corner of a lane's label. */
export function labelOrigin(lane: number): { x: number; y: number } {
  return { x: WORLD.pad, y: WORLD.pad + lane * WORLD_ROW }
}

/** The top-left corner of a tile's poster. */
export function tileOrigin(at: WorldPlace): { x: number; y: number } {
  return {
    x: WORLD.pad + at.column * WORLD.column,
    y: WORLD.pad + at.lane * WORLD_ROW + WORLD.labelHeight,
  }
}

/** The SVG path of a rung between two lanes. */
export function rungPath(rung: { upper: WorldPlace; lower: WorldPlace }): {
  d: string
  end: { x: number; y: number }
} {
  const top = tileOrigin(rung.upper)
  const bottom = tileOrigin(rung.lower)
  const x1 = top.x + WORLD.tileWidth / 2
  const y1 = top.y + WORLD.posterHeight + WORLD.captionHeight
  const x2 = bottom.x + WORLD.tileWidth / 2
  const y2 = bottom.y - WORLD.labelHeight - 4
  const bend = (y2 - y1) / 2
  return {
    d: `M ${x1} ${y1} C ${x1} ${y1 + bend}, ${x2} ${y2 - bend}, ${x2} ${y2}`,
    end: { x: x2, y: y2 },
  }
}
