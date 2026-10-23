import { z } from 'zod'
import { MEDIA_TYPES } from '../media'

// Server-only: imported by server-function files, never by client code. An exported schema in a
// file that also exports server functions survives the split and pulls zod into the browser.

/** A title by Aaru id, by provider ids, or by title and year, as the server's `MediaRef`. */
export const mediaRef = z.object({
  titleId: z.string().uuid().optional(),
  type: z.enum(MEDIA_TYPES),
  ids: z.record(z.string(), z.string()).optional(),
  title: z.string().optional(),
  year: z.number().int().optional(),
})
