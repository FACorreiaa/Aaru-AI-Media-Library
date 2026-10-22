// Its own module, so Home's medallion does not carry the profile's formatting with it.

/** Up to two letters for the medallion: "Ana Lopes" → "AL", "ana" → "A", "@reed" → "R". */
export function initials(person: {
  displayName: string | null
  handle: string | null
}): string | null {
  const words = (person.displayName ?? '').split(/\s+/).filter(Boolean)
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase()
  if (words.length === 1) return words[0][0].toUpperCase()
  return person.handle ? person.handle[0].toUpperCase() : null
}
