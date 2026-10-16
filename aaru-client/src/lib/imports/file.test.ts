import { describe, expect, it } from 'vitest'
import { MAX_IMPORT_BYTES, isGzip, readImportFile } from './file'

async function gzip(text: string): Promise<Uint8Array<ArrayBuffer>> {
  const stream = new Blob([text])
    .stream()
    .pipeThrough(new CompressionStream('gzip'))
  return new Uint8Array(await new Response(stream).arrayBuffer())
}

const xml =
  '<?xml version="1.0"?><myanimelist><anime><series_animedb_id>1</series_animedb_id></anime></myanimelist>'

describe('import files', () => {
  it('reads a gzipped MyAnimeList export as its XML', async () => {
    const packed = await gzip(xml)
    expect(isGzip(packed)).toBe(true)
    expect(await readImportFile(new Blob([packed]))).toBe(xml)
  })

  it('reads a plain file unchanged', async () => {
    expect(await readImportFile(new Blob([xml]))).toBe(xml)
    expect(isGzip(new TextEncoder().encode(xml))).toBe(false)
  })

  it('refuses an export that inflates past the upload limit', async () => {
    const packed = await gzip('a'.repeat(MAX_IMPORT_BYTES + 1))
    expect(packed.byteLength).toBeLessThan(MAX_IMPORT_BYTES)
    await expect(readImportFile(new Blob([packed]))).rejects.toThrow('5 MB')
  })

  it('says so when a .gz file is broken', async () => {
    const broken = new Uint8Array([0x1f, 0x8b, 1, 2, 3])
    await expect(readImportFile(new Blob([broken]))).rejects.toThrow(
      'could not be opened',
    )
  })
})
