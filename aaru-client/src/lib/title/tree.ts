import type { components } from '../api/schema'
import { kindOf, statusLabel } from '../library/model'
import type { MediaKind } from '../library/model'

// GRAPH-005 on the web: a title tree ("From here") as the server picked it. Nothing here decides
// which titles are in it; this only places the tiles and names what the server sent.

export type TitleTree = components['schemas']['TitleTree']
export type TreeBranch = components['schemas']['TreeBranch']
export type TreeNode = components['schemas']['TreeNode']
export type TreeBranchKind = components['schemas']['TreeBranchKind']

/** A tile is a 2:3 poster; an album's square cover sits at its foot. */
export const TREE = {
  TILE_W: 72,
  TILE_H: 108,
  /** Between tiles in a row. */
  GAP: 24,
  /** Between the root and the first tile of each row: room for the trunk. */
  TRUNK_GAP: 44,
  /** A row's label, above its tiles. */
  LABEL_H: 24,
  /** A tile's name and year, under it. */
  CAPTION_H: 52,
  ROW_GAP: 12,
  /** Room for a tile's ring. */
  PAD: 4,
} as const

const ROW_H = TREE.LABEL_H + TREE.TILE_H + TREE.CAPTION_H + TREE.ROW_GAP

export interface PlacedTile {
  node: TreeNode
  x: number
  y: number
}

export interface PlacedRow {
  branch: TreeBranch
  /** Where the row's label starts. */
  x: number
  y: number
  tiles: PlacedTile[]
}

export interface TreeConnector {
  d: string
  /** True when the line leads into a title the person finished: drawn in the accent. */
  lit: boolean
}

export interface TreeLayout {
  width: number
  height: number
  root: PlacedTile
  rows: PlacedRow[]
  connectors: TreeConnector[]
}

/**
 * Places a tree the way a game's skill tree reads: the root on the left, a trunk down from it,
 * and each branch a row to its right. Lines are straight or turn at right angles, and run
 * through the middle of the tiles.
 */
export function treeLayout(tree: TitleTree): TreeLayout {
  const { TILE_W, TILE_H, GAP, TRUNK_GAP, LABEL_H, PAD } = TREE
  const rootX = PAD
  const firstX = rootX + TILE_W + TRUNK_GAP
  const trunkX = rootX + TILE_W + TRUNK_GAP / 2
  const tileY = (row: number) => PAD + row * ROW_H + LABEL_H
  const midY = (row: number) => tileY(row) + TILE_H / 2

  const rows: PlacedRow[] = tree.branches.map((branch, row) => ({
    branch,
    x: firstX,
    y: PAD + row * ROW_H,
    tiles: branch.nodes.map((node, i) => ({
      node,
      x: firstX + i * (TILE_W + GAP),
      y: tileY(row),
    })),
  }))

  const connectors: TreeConnector[] = []
  rows.forEach((row, r) => {
    if (row.tiles.length === 0) return
    const first = row.tiles[0]
    const y = midY(r)
    // Root to the row's first tile: straight for the first row, down the trunk for the others.
    connectors.push({
      d:
        r === 0
          ? `M ${rootX + TILE_W} ${y} H ${first.x}`
          : `M ${trunkX} ${midY(0)} V ${y} H ${first.x}`,
      lit: isLit(first.node),
    })
    for (let i = 1; i < row.tiles.length; i++) {
      const from = row.tiles[i - 1]
      const to = row.tiles[i]
      connectors.push({
        d: `M ${from.x + TILE_W} ${y} H ${to.x}`,
        lit: isLit(to.node),
      })
    }
  })

  const longest = Math.max(0, ...rows.map((r) => r.tiles.length))
  return {
    width: firstX + Math.max(0, longest * TILE_W + (longest - 1) * GAP) + PAD,
    height: PAD + Math.max(1, rows.length) * ROW_H - TREE.ROW_GAP + PAD,
    root: { node: tree.root, x: rootX, y: tileY(0) },
    rows,
    connectors,
  }
}

/** How a tile looks: the root ringed, a finished title lit, one in the library plain, one the
 * person does not have dimmed. */
export type TileState = 'root' | 'lit' | 'library' | 'locked'

export function tileState(node: TreeNode): TileState {
  if (node.pick === 'root') return 'root'
  if (isLit(node)) return 'lit'
  return node.status ? 'library' : 'locked'
}

function isLit(node: TreeNode): boolean {
  return node.status === 'finished'
}

export function treeNodeKind(node: TreeNode): MediaKind {
  return kindOf(node.ref.type, node.isAnime ?? false)
}

const PERSON: Partial<Record<TreeBranchKind, string>> = {
  director: 'Director',
  creator: 'Creator',
  studio: 'Studio',
  author: 'Author',
  artist: 'Artist',
}

/** "Director · Denis Villeneuve", "Series", "Adaptations". */
export function branchLabel(branch: TreeBranch): string {
  if (branch.kind === 'series') return 'Series'
  if (branch.kind === 'adaptation') return 'Adaptations'
  const role = PERSON[branch.kind] ?? 'By'
  return branch.label ? `${role} · ${branch.label}` : role
}

export function treeNodeYear(node: TreeNode): string | null {
  return node.releaseDate?.slice(0, 4) ?? node.ref.year?.toString() ?? null
}

/** What a screen reader hears for a tile: "Dune, 2021, best known, Plan to watch". */
export function treeNodeLabel(node: TreeNode): string {
  const kind = treeNodeKind(node)
  return [
    node.ref.title ?? 'Untitled',
    treeNodeYear(node),
    node.pick === 'best_known' ? 'best known' : null,
    node.status ? statusLabel(node.status, kind) : 'not in your library',
  ]
    .filter(Boolean)
    .join(', ')
}

/** True when there is something to draw: a tree with no branch is not shown at all. */
export function hasBranches(tree: TitleTree | null | undefined): boolean {
  return !!tree && tree.branches.some((b) => b.nodes.length > 0)
}
