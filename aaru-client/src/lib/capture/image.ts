import { MAX_CAPTURE_PICTURES, captureSlices } from './model'

// AG-006: a picture is read at most 1568 px on its long edge (what the model looks at anyway), so
// the browser shrinks it and sends JPEGs: one, or several for a tall scrolling screenshot
// (BOOK-002). Loaded only when a picture is chosen.

const LONG_EDGE = 1568

export type CaptureImage = { image: string; mediaType: 'image/jpeg' }

export async function capturePieces(file: Blob): Promise<CaptureImage[]> {
  const bitmap = await createImageBitmap(file).catch(() => {
    throw new Error('This browser cannot open that picture. Try a JPEG or PNG.')
  })
  try {
    const slices = captureSlices(bitmap.width, bitmap.height)
    if (slices.length > MAX_CAPTURE_PICTURES)
      throw new Error("That's long. Paste the text instead.")
    return await Promise.all(
      slices.map(({ top, height }) => encode(bitmap, top, height)),
    )
  } finally {
    bitmap.close()
  }
}

async function encode(
  bitmap: ImageBitmap,
  top: number,
  height: number,
): Promise<CaptureImage> {
  const scale = Math.min(1, LONG_EDGE / Math.max(bitmap.width, height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(height * scale)
  const context = canvas.getContext('2d')
  if (!context) throw new Error('This browser cannot open that picture.')
  context.drawImage(
    bitmap,
    0,
    top,
    bitmap.width,
    height,
    0,
    0,
    canvas.width,
    canvas.height,
  )
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, 'image/jpeg', 0.85),
  )
  if (!blob) throw new Error('This browser cannot open that picture.')
  const bytes = new Uint8Array(await blob.arrayBuffer())
  let binary = ''
  for (let i = 0; i < bytes.length; i += 0x8000)
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return { image: btoa(binary), mediaType: 'image/jpeg' }
}
