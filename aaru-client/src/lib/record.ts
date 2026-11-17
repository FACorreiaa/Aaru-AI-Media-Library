/** Whether a value read from outside (parsed JSON, a posted message) is an object whose fields
 *  can be looked at. An array is one too; callers check the fields they need. */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
