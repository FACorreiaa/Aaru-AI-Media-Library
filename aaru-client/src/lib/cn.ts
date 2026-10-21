import { clsx } from 'clsx'

/**
 * Joins class names, dropping falsy ones. No tailwind-merge (about 8 KB): components expose
 * variants, and callers add classes that do not fight them rather than overriding them.
 */
export const cn = clsx
