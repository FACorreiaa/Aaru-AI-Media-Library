/** Uploads are capped at this size after decompression, like the server's limit. */
export const MAX_IMPORT_BYTES = 5 * 1024 * 1024

const TOO_LARGE = 'That file is larger than 5 MB. Check it is the right export.'

/** gzip's magic number: MyAnimeList's export downloads as `animelist_….xml.gz`. */
export function isGzip(bytes: Uint8Array): boolean {
  return bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b
}

/** Inflates gzip in the browser, refusing to grow past the upload limit. */
export async function gunzip(
  bytes: Uint8Array<ArrayBuffer>,
): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([bytes])
    .stream()
    .pipeThrough(new DecompressionStream('gzip'))
  const reader = stream.getReader()
  const chunks: Uint8Array[] = []
  let size = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    size += value.byteLength
    if (size > MAX_IMPORT_BYTES) {
      await reader.cancel()
      throw new Error(TOO_LARGE)
    }
    chunks.push(value)
  }
  const out = new Uint8Array(size)
  let offset = 0
  for (const chunk of chunks) {
    out.set(chunk, offset)
    offset += chunk.byteLength
  }
  return out
}

/** The export as text: gzip is inflated first; either way it must fit the upload limit. */
export async function readImportFile(file: Blob): Promise<string> {
  if (file.size > MAX_IMPORT_BYTES) throw new Error(TOO_LARGE)
  let bytes = new Uint8Array(await file.arrayBuffer())
  if (isGzip(bytes)) {
    try {
      bytes = await gunzip(bytes)
    } catch (error) {
      if (error instanceof Error && error.message === TOO_LARGE) throw error
      throw new Error(
        'That .gz file could not be opened. Try the .xml inside it.',
      )
    }
  }
  return new TextDecoder().decode(bytes)
}
