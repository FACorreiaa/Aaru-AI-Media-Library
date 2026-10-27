// SOC-001b: the browser makes the avatar the server keeps, a 512 px square JPEG cut from the
// middle of the photo. The original never leaves the device. Loaded only when a photo is chosen.

const SIDE = 512

export async function squareAvatar(file: Blob): Promise<string> {
  const bitmap = await createImageBitmap(file).catch(() => {
    throw new Error('This browser cannot open that photo. Try a JPEG or PNG.')
  })
  const crop = Math.min(bitmap.width, bitmap.height)
  const side = Math.min(SIDE, crop)
  const canvas = document.createElement('canvas')
  canvas.width = side
  canvas.height = side
  const context = canvas.getContext('2d')
  if (!context) throw new Error('This browser cannot open that photo.')
  context.drawImage(
    bitmap,
    (bitmap.width - crop) / 2,
    (bitmap.height - crop) / 2,
    crop,
    crop,
    0,
    0,
    side,
    side,
  )
  bitmap.close()
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, 'image/jpeg', 0.85),
  )
  if (!blob) throw new Error('This browser cannot open that photo.')
  const bytes = new Uint8Array(await blob.arrayBuffer())
  let binary = ''
  for (let i = 0; i < bytes.length; i += 0x8000)
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(binary)
}
