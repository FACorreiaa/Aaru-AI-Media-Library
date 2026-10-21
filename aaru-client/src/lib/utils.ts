import { clsx } from 'clsx'
import type { ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

/**
 * Joins class names and lets a later Tailwind class win over an earlier one of the same kind,
 * so a caller's `p-5` replaces a component's `py-6`. The one `cn` in the client; the
 * shadcn-solid components use `cx` from `./cva`, which merges the same way.
 */
export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs))
