// ASK-010 on the web: what the card does before a file goes to the server. The server reads every
// file's bytes and decides what it is; this only shrinks pictures as capture does, turns a long
// paste into a text file, and keeps the obvious refusals off the network.

/** What the card's picker offers. The server is the judge of what is inside. */
export const ACCEPT = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/heic',
  'application/pdf',
  'text/plain',
  'text/markdown',
  'text/csv',
  'text/calendar',
  'application/json',
  'application/xml',
  '.csv',
  '.tsv',
  '.txt',
  '.md',
  '.xml',
  '.gz',
  '.ics',
  '.json',
  '.pdf',
].join(',')

/** Files one turn carries. */
export const MAX_TURN_FILES = 5
/** The largest file the API reads: a listening history. */
export const MAX_FILE_BYTES = 24 << 20
/** A paste longer than a typed question is sent as a text file instead. */
export const PASTE_AS_FILE = 4000

export type Piece = { blob: Blob; name: string }

export function isPicture(file: Blob): boolean {
  return file.type.startsWith('image/')
}

/** A long paste as the text file the server reads; no name, so the chip says "Pasted text". */
export function pastedText(text: string): Piece {
  return { blob: new Blob([text], { type: 'text/plain' }), name: '' }
}

/**
 * A chosen file as what is sent: a picture shrunk to JPEG as capture does (a tall screenshot in
 * up to five pieces), anything else as it is.
 */
export async function piecesOf(file: File): Promise<Piece[]> {
  if (file.size > MAX_FILE_BYTES)
    throw new Error(`${file.name} is larger than 24 MB.`)
  if (!isPicture(file)) return [{ blob: file, name: file.name }]
  const { capturePieces } = await import('../capture/image')
  const pieces = await capturePieces(file)
  const base = file.name.replace(/\.[^.]+$/, '') || 'Picture'
  return pieces.map((piece, i) => ({
    blob: new Blob([fromBase64(piece.image)], { type: piece.mediaType }),
    name:
      pieces.length > 1
        ? `${base} (${i + 1} of ${pieces.length}).jpg`
        : `${base}.jpg`,
  }))
}

function fromBase64(data: string): Uint8Array<ArrayBuffer> {
  const binary = atob(data)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}
