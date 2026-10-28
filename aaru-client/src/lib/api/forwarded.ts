/** `X-Forwarded-For` for one plausible IPv4 or IPv6 address; nothing for anything else. */
export function forwardedFor(
  address: string | null | undefined,
): Record<string, string> {
  if (!address || !/^[0-9A-Fa-f:.]{2,45}$/.test(address)) return {}
  return { 'X-Forwarded-For': address }
}
