import type { components } from './api/schema'

/** What a title is on the wire: `album` (MUS-001) is a MusicBrainz release group. */
export type MediaType = components['schemas']['MediaType']

// A record, not a list, so the schema gaining a type fails to compile here first.
const ALL: Record<MediaType, true> = {
  movie: true,
  show: true,
  book: true,
  album: true,
}

/** Every media type, in stored order: the one list validators enumerate (`z.enum`). */
export const MEDIA_TYPES = Object.keys(ALL) as [MediaType, ...MediaType[]]
