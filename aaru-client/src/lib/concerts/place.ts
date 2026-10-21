import type { components } from '../api/schema'

// The "Concerts near" city's pure part (MUS-003), on its own so Settings' Account page, which
// only names the saved city, does not load the rest of the concerts model.

type ConcertPlace = components['schemas']['ConcertPlace']

/** "Porto, Porto District, Portugal": the name, then the region and country when they add. */
export function placeLabel(place: ConcertPlace): string {
  const parts: string[] = []
  for (const part of [place.name, place.region, place.country]) {
    const text = part?.trim()
    if (text && !parts.includes(text)) parts.push(text)
  }
  return parts.join(', ')
}

/** A city search worth sending: 2 to 100 characters once trimmed, else null. */
export function placeQuery(text: string): string | null {
  const query = text.trim()
  return query.length >= 2 && query.length <= 100 ? query : null
}
