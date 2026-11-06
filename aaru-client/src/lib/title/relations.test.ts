import { describe, expect, it } from 'vitest'
import { edgeLabel, nodeCaption, relatedGroups } from './relations'
import type { RelationGraph, RelationNode } from './relations'

const node = (
  key: string,
  extra: Partial<RelationNode> = {},
): RelationNode => ({
  key,
  ref: { type: 'movie', ids: { tmdb: key }, title: key },
  rank: 0,
  lane: 0,
  mainChain: false,
  centre: false,
  ...extra,
})

describe('relatedGroups', () => {
  const graph: RelationGraph = {
    order: 'release',
    storyOrderAvailable: false,
    partial: false,
    nodes: [
      node('book', { lane: 1 }),
      node('one', { mainChain: true }),
      node('two', { mainChain: true, rank: 1, centre: true }),
      node('three', { mainChain: true, rank: 2 }),
      node('far', { rank: 2, lane: 1 }),
    ],
    edges: [
      { from: 'one', to: 'two', relation: 'sequel' },
      { from: 'two', to: 'three', relation: 'sequel' },
      { from: 'book', to: 'two', relation: 'adaptation' },
      { from: 'three', to: 'far', relation: 'adaptation' },
    ],
  }

  it('reads each edge from the title on screen', () => {
    const groups = relatedGroups(graph, 'two')
    expect(groups.map((g) => [g.group, g.nodes.map((n) => n.key)])).toEqual([
      ['before', ['one']],
      ['after', ['three']],
      ['basedOn', ['book']],
    ])
  })

  it('leaves out titles two steps away', () => {
    const keys = relatedGroups(graph, 'two').flatMap((g) =>
      g.nodes.map((n) => n.key),
    )
    expect(keys).not.toContain('far')
  })
})

describe('labels', () => {
  it('names the format and year, and leaves the main chain unlabelled', () => {
    expect(
      nodeCaption(node('x', { releaseDate: '2013-12-09', format: 'ova' })),
    ).toBe('2013 · OVA')
    expect(nodeCaption(node('x', { format: 'unknown' }))).toBe('')
    expect(edgeLabel('sequel')).toBeNull()
    expect(edgeLabel('adaptation')).toBe('adapted')
  })
})
