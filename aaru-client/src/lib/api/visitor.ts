/**
 * The headers that name a web visitor to the API (`X-Aaru-Visitor`), proved with the secret the
 * Worker and the API share (`X-Aaru-Web-Secret`). The API trusts the address only with that
 * secret and uses it for nothing but per-address limits. Nothing without a secret or for anything
 * but one plain IPv4 or IPv6 address.
 */
export function visitorHeaders(
  address: string | null | undefined,
  secret: string | undefined,
): Record<string, string> {
  if (!secret || !address || !/^[0-9A-Fa-f:.]{2,45}$/.test(address)) return {}
  return { 'X-Aaru-Visitor': address, 'X-Aaru-Web-Secret': secret }
}
