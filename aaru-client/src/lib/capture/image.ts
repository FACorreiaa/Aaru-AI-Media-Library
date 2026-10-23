// AG-006: a picture is read at most 1568 px on its long edge (what the model looks at anyway),
// so the browser shrinks it and sends a JPEG. Loaded only when a picture is chosen.

const LONG_EDGE = 1568

export async function shrinkImage(
  file: Blob,
): Promise<{ image: string; mediaType: 'image/jpeg' }> {
  const bitmap = await createImageBitmap(file).catch(() => {
    throw new Error('This browser cannot open that picture. Try a JPEG or PNG.')
  })
  const scale = Math.min(1, LONG_EDGE / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(bitmap.height * scale)
  const context = canvas.getContext('2d')
  if (!context) throw new Error('This browser cannot open that picture.')
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()
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
