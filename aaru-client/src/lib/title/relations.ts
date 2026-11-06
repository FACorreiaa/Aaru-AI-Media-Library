import type { components } from '../api/schema'
import { kindOf } from '../library/model'
import type { MediaKind } from '../library/model'

// GRAPH-002 on the web: a title's relations (GRAPH-001), as the server placed them. Nothing here
// decides an order or a layout; it only names what the server sent.

export type RelationGraph = components['schemas']['RelationGraph']
export type RelationNode = components['schemas']['RelationNode']
export type RelationEdge = components['schemas']['RelationEdge']
export type Relation = components['schemas']['Relation']
export type RelationOrder = components['schemas']['RelationOrder']

/** How a related title stands to the one on screen, as a group heading. */
export type RelatedGroup =
  | 'before'
  | 'after'
  | 'basedOn'
  | 'adaptations'
  | 'mainStory'
  | 'sideStories'
  | 'spinOffs'
  | 'alternatives'
  | 'summaries'
  | 'other'

export const RELATED_GROUP_LABELS: Record<RelatedGroup, string> = {
  before: 'Before',
  after: 'After',
  basedOn: 'Based on',
  adaptations: 'Adaptations',
  mainStory: 'Main story',
  sideStories: 'Side stories',
  spinOffs: 'Spin-offs',
  alternatives: 'Other versions',
  summaries: 'Recaps',
  other: 'Related',
}

const GROUP_ORDER: RelatedGroup[] = [
  'before',
  'after',
  'basedOn',
  'adaptations',
  'mainStory',
  'sideStories',
  'spinOffs',
  'alternatives',
  'summaries',
  'other',
]

/** The group a node lands in, read from an edge: `to` is `from`'s relation. `outward` is true when
 * the node on screen is `from`. */
function groupOf(relation: Relation, outward: boolean): RelatedGroup {
  switch (relation) {
    case 'sequel':
      return outward ? 'after' : 'before'
    case 'prequel':
      return outward ? 'before' : 'after'
    case 'adaptation':
      return outward ? 'adaptations' : 'basedOn'
    case 'source':
      return outward ? 'basedOn' : 'adaptations'
    case 'side_story':
      return outward ? 'sideStories' : 'mainStory'
    case 'parent':
      return outward ? 'mainStory' : 'sideStories'
    case 'spin_off':
      return 'spinOffs'
    case 'alternative':
      return 'alternatives'
    case 'summary':
      return 'summaries'
    default:
      return 'other'
  }
}

/** The titles directly related to `centreKey`, grouped and in the server's order. */
export function relatedGroups(
  graph: RelationGraph,
  centreKey: string,
): Array<{ group: RelatedGroup; nodes: RelationNode[] }> {
  const byKey = new Map(graph.nodes.map((n) => [n.key, n]))
  const found = new Map<RelatedGroup, RelationNode[]>()
  const seen = new Set<string>()
  for (const edge of graph.edges) {
    const outward = edge.from === centreKey
    if (!outward && edge.to !== centreKey) continue
    const other = byKey.get(outward ? edge.to : edge.from)
    if (!other || seen.has(other.key)) continue
    seen.add(other.key)
    const group = groupOf(edge.relation, outward)
    found.set(group, [...(found.get(group) ?? []), other])
  }
  const order = new Map(graph.nodes.map((n, i) => [n.key, i]))
  return GROUP_ORDER.filter((g) => found.has(g)).map((group) => ({
    group,
    nodes: found
      .get(group)!
      .sort((a, b) => (order.get(a.key) ?? 0) - (order.get(b.key) ?? 0)),
  }))
}

/** The node the graph was asked for. */
export function centreOf(graph: RelationGraph): RelationNode | undefined {
  return graph.nodes.find((n) => n.centre)
}

export function nodeKind(node: RelationNode): MediaKind {
  return kindOf(node.ref.type, node.isAnime ?? false)
}

/** "2013 · OVA": what tells two titles of one name apart. */
export function nodeCaption(node: RelationNode): string {
  const year = node.releaseDate?.slice(0, 4) ?? node.ref.year?.toString()
  const format = FORMAT_LABELS[node.format ?? ''] ?? null
  return [year, format].filter(Boolean).join(' · ')
}

const FORMAT_LABELS: Record<string, string> = {
  tv: 'TV',
  tv_short: 'TV short',
  movie: 'Film',
  ova: 'OVA',
  ona: 'ONA',
  special: 'Special',
  manga: 'Manga',
  novel: 'Light novel',
  one_shot: 'One-shot',
}

/** A short label for an edge drawn in the graph; the main chain needs none. */
export function edgeLabel(relation: Relation): string | null {
  switch (relation) {
    case 'sequel':
    case 'prequel':
      return null
    case 'adaptation':
      return 'adapted'
    case 'source':
      return 'source'
    case 'side_story':
      return 'side story'
    case 'parent':
      return 'main story'
    case 'spin_off':
      return 'spin-off'
    case 'alternative':
      return 'other version'
    case 'summary':
      return 'recap'
    default:
      return 'related'
  }
}
