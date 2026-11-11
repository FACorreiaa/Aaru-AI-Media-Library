import { describe, expect, it } from 'vitest'
import {
  TREE,
  branchLabel,
  hasBranches,
  tileState,
  treeLayout,
  treeNodeLabel,
} from './tree'
import type { TitleTree, TreeNode } from './tree'

const node = (key: string, extra: Partial<TreeNode> = {}): TreeNode => ({
  key,
  ref: { type: 'movie', ids: { tmdb: key }, title: key, year: 2020 },
  pick: 'next',
  ...extra,
})

const tree: TitleTree = {
  partial: false,
  root: node('root', { pick: 'root', status: 'finished' }),
  branches: [
    {
      kind: 'director',
      label: 'Denis Villeneuve',
      nodes: [
        node('a', { status: 'finished' }),
        node('b', { status: 'wishlist' }),
        node('c', { pick: 'best_known' }),
      ],
    },
    { kind: 'series', nodes: [node('s')] },
  ],
}

describe('treeLayout', () => {
  const layout = treeLayout(tree)
  const { TILE_W, TILE_H, GAP, TRUNK_GAP, LABEL_H, PAD } = TREE

  it('puts the root on the left and each branch in a row to its right', () => {
    expect(layout.root).toMatchObject({ x: PAD, y: PAD + LABEL_H })
    const first = PAD + TILE_W + TRUNK_GAP
    expect(layout.rows[0].tiles.map((t) => t.x)).toEqual([
      first,
      first + TILE_W + GAP,
      first + 2 * (TILE_W + GAP),
    ])
    expect(layout.rows[0].tiles[0].y).toBe(layout.root.y)
    expect(layout.rows[1].tiles[0].y).toBeGreaterThan(
      layout.rows[0].tiles[0].y + TILE_H,
    )
    expect(layout.width).toBe(first + 3 * TILE_W + 2 * GAP + PAD)
  })

  it('joins tiles with straight and right-angle lines only', () => {
    expect(layout.connectors).toHaveLength(4)
    for (const c of layout.connectors)
      expect(c.d).toMatch(/^M [\d.]+ [\d.]+( [HV] [\d.]+)+$/)
    const mid = PAD + LABEL_H + TILE_H / 2
    expect(layout.connectors[0].d).toBe(
      `M ${PAD + TILE_W} ${mid} H ${PAD + TILE_W + TRUNK_GAP}`,
    )
    // The second row hangs from the trunk: down, then across.
    expect(layout.connectors[3].d).toMatch(
      /^M [\d.]+ [\d.]+ V [\d.]+ H [\d.]+$/,
    )
  })

  it('lights the line into a finished title', () => {
    expect(layout.connectors.map((c) => c.lit)).toEqual([
      true,
      false,
      false,
      false,
    ])
  })

  it('draws a root alone without rows', () => {
    const alone = treeLayout({ ...tree, branches: [] })
    expect(alone.rows).toEqual([])
    expect(alone.connectors).toEqual([])
    expect(alone.width).toBe(PAD + TILE_W + TRUNK_GAP + PAD)
  })
})

describe('tiles', () => {
  it('reads a state from the pick and the status', () => {
    expect(tileState(tree.root)).toBe('root')
    expect(tileState(node('a', { status: 'finished' }))).toBe('lit')
    expect(tileState(node('b', { status: 'on_hold' }))).toBe('library')
    expect(tileState(node('c'))).toBe('locked')
  })

  it('names a tile for a screen reader', () => {
    expect(treeNodeLabel(node('Dune', { pick: 'best_known' }))).toBe(
      'Dune, 2020, best known, not in your library',
    )
    expect(
      treeNodeLabel(
        node('Dune', { status: 'wishlist', releaseDate: '2021-09-15' }),
      ),
    ).toBe('Dune, 2021, Plan to watch')
  })

  it('labels a branch by who or what it is', () => {
    expect(branchLabel(tree.branches[0])).toBe('Director · Denis Villeneuve')
    expect(branchLabel(tree.branches[1])).toBe('Series')
    expect(branchLabel({ kind: 'adaptation', nodes: [] })).toBe('Adaptations')
  })

  it('has nothing to show without a branch', () => {
    expect(hasBranches(tree)).toBe(true)
    expect(hasBranches({ ...tree, branches: [] })).toBe(false)
    expect(hasBranches(null)).toBe(false)
  })
})
