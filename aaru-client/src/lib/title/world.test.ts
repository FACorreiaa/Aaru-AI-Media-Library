import { describe, expect, it } from 'vitest'
import {
  WORLD,
  WORLD_ROW,
  countLabel,
  isReady,
  kindsLabel,
  laneCount,
  missingCount,
  progressShare,
  rungPath,
  tileOrigin,
  titleLabel,
  worldLayout,
} from './world'
import type { World, WorldTitle } from './world'

const title = (
  key: string,
  name: string,
  year: number,
  extra: Partial<WorldTitle> = {},
): WorldTitle => ({
  key,
  ref: { type: 'movie', title: name, year },
  side: false,
  next: false,
  ...extra,
})

const have = (key: string, status: WorldTitle['status']) => ({
  libraryItemId: `item-${key}`,
  status,
})

const dune: World = {
  state: 'ready',
  id: 'w',
  name: 'Dune',
  total: 5,
  finished: 2,
  kinds: ['book', 'film', 'show'],
  lanes: [
    {
      kind: 'book',
      titles: [
        title('b1', 'Dune', 1965, have('b1', 'finished')),
        title('b2', 'Dune Messiah', 1969, { next: true }),
      ],
    },
    {
      kind: 'film',
      titles: [
        title('f1', 'Dune: Part One', 2021, have('f1', 'finished')),
        title('f2', 'Dune: Part Two', 2024, have('f2', 'in_progress')),
      ],
    },
    {
      kind: 'show',
      titles: [title('s1', 'Dune: Prophecy', 2024, { side: true })],
    },
  ],
  links: [
    { from: 'b1', to: 'b2', relation: 'sequel' },
    { from: 'b1', to: 'f1', relation: 'adaptation' },
    { from: 'f1', to: 'f2', relation: 'sequel' },
    { from: 's1', to: 'f1', relation: 'spin_off' },
  ],
  startHere: 'f2',
  anchor: 'f1',
  truncated: false,
  partial: false,
}

describe('worlds (GRAPH-007)', () => {
  it('reads the count and kinds as words', () => {
    expect(countLabel(5, 11)).toBe('5 of 11')
    expect(kindsLabel(['book', 'film', 'show'])).toBe('Books, Films, and Shows')
    expect(kindsLabel(['anime'])).toBe('Anime')
    expect(progressShare(1, 4)).toBe(0.25)
    expect(progressShare(0, 0)).toBe(0)
    expect(progressShare(9, 4)).toBe(1)
  })

  it('says where the viewer stands on each title', () => {
    const [books, films, shows] = dune.lanes
    expect(titleLabel(books.titles[0], 'book', false)).toBe('Dune, 1965, Read')
    expect(titleLabel(books.titles[1], 'book', false)).toBe(
      'Dune Messiah, 1969, not in your library, next in this lane',
    )
    expect(titleLabel(films.titles[1], 'film', true)).toBe(
      'Dune: Part Two, 2024, Watching, start here',
    )
    expect(titleLabel(shows.titles[0], 'show', false)).toBe(
      'Dune: Prophecy, 2024, side story, not in your library',
    )
  })

  it('counts each lane and what Add the rest would plan', () => {
    expect(dune.lanes.map(laneCount)).toEqual([
      { finished: 1, total: 2 },
      { finished: 1, total: 2 },
      { finished: 0, total: 1 },
    ])
    expect(missingCount(dune)).toBe(2)
  })

  it('is ready only once built with two titles', () => {
    expect(isReady(dune)).toBe(true)
    expect(isReady({ ...dune, state: 'building', total: 0 })).toBe(false)
    expect(isReady({ ...dune, total: 1 })).toBe(false)
    expect(isReady(null)).toBe(false)
  })

  it('puts tiles in a row per lane and joins lanes with rungs', () => {
    const layout = worldLayout(dune)
    const first = tileOrigin({ lane: 0, column: 0 })
    const second = tileOrigin({ lane: 0, column: 1 })
    expect(second.x - first.x).toBe(WORLD.column)
    expect(second.y).toBe(first.y)
    expect(tileOrigin({ lane: 1, column: 0 }).y - first.y).toBe(WORLD_ROW)
    expect(layout.width).toBe(WORLD.pad * 2 + WORLD.column + WORLD.tileWidth)
    expect(layout.height).toBe(WORLD.pad + 3 * WORLD_ROW)

    // Two links cross lanes; each is drawn from the upper lane down, whichever way it points.
    expect(layout.rungs).toEqual([
      { upper: { lane: 0, column: 0 }, lower: { lane: 1, column: 0 } },
      { upper: { lane: 1, column: 0 }, lower: { lane: 2, column: 0 } },
    ])
    // A rung stops above the lower lane's label, over the column it joins.
    const rung = rungPath(layout.rungs[0])
    const lower = tileOrigin({ lane: 1, column: 0 })
    expect(rung.end.x).toBe(lower.x + WORLD.tileWidth / 2)
    expect(rung.end.y).toBeLessThan(lower.y - WORLD.labelHeight)
  })
})
