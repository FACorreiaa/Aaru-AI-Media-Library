// Its own module, apart from `model.ts`: `lib/queries.ts` rides along with every page's
// loaders, and must not bring the achievements copy with it.

/** The cache key `/v1/me/progress` lives under (`progressQuery`, `UnlockWatcher`, Home). */
export const PROGRESS_KEY = ['progress']
