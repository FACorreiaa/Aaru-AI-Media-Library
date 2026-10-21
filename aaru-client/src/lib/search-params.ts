// Readers for routes' `validateSearch`. Route options are not code-split: they ship in the entry
// chunk every page loads, the landing included, so validating with zod here put ~24 KB gzip on
// every first visit. A param that does not parse reads as absent, never as an error page.

export function optionalString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined
}

export function optionalBoolean(value: unknown): boolean | undefined {
  return typeof value === 'boolean' ? value : undefined
}

export function optionalEnum<T extends string>(
  value: unknown,
  options: readonly T[],
): T | undefined {
  return options.includes(value as T) ? (value as T) : undefined
}

/** An integer in `min...max`, from a number or a numeric string (the router parses `?year=2026`
 *  to a number, a hand-typed URL may not). */
export function optionalInt(
  value: unknown,
  min: number,
  max: number,
): number | undefined {
  const n =
    typeof value === 'number'
      ? value
      : typeof value === 'string' && value.trim() !== ''
        ? Number(value)
        : Number.NaN
  return Number.isInteger(n) && n >= min && n <= max ? n : undefined
}
