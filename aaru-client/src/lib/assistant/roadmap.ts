import type { components } from '../api/schema'

// ASK-011: the list a chat turn planned, as Aaru named it, before any title is matched. Words
// for the RoadmapCard; no rule lives here.

export type ChatRoadmap = components['schemas']['ChatRoadmap']
export type ChatRoadmapItem = components['schemas']['ChatRoadmapItem']

const KIND: Record<ChatRoadmapItem['type'], string> = {
  movie: 'Film',
  show: 'Show',
  book: 'Book',
  manga: 'Manga',
}

/** "Film · 2022", "Book · Jonathan Hickman": what tells one title from another of its name. */
export function itemLine(item: ChatRoadmapItem): string {
  const parts = [KIND[item.type]]
  if (item.author) parts.push(item.author)
  if (item.year !== undefined) parts.push(String(item.year))
  return parts.join(' · ')
}

export function titleCount(roadmap: ChatRoadmap): number {
  return roadmap.steps.reduce((n, step) => n + step.items.length, 0)
}

/** "12 titles in 4 steps", or "12 titles" for a plain list. */
export function roadmapSummary(roadmap: ChatRoadmap): string {
  const titles = titleCount(roadmap)
  const counted = titles === 1 ? '1 title' : `${titles} titles`
  const staged = roadmap.steps.filter((step) => step.heading).length
  if (staged === 0) return counted
  return `${counted} in ${staged === 1 ? '1 step' : `${staged} steps`}`
}

/** Whether this title starts a pair read side by side: the next one shares its number. */
export function startsPair(items: ChatRoadmapItem[], index: number): boolean {
  const pair = items[index]?.pair
  if (pair === undefined) return false
  return items[index - 1]?.pair !== pair && items[index + 1]?.pair === pair
}
