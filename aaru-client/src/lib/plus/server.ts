import { createServerFn } from '@tanstack/solid-start'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'

// BIL-001 on the web: Aaru Plus as the server keeps it. Bought in the Apple apps only; the web
// shows it and sells nothing.

export type Entitlement = components['schemas']['Entitlement']

export const getEntitlement = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Entitlement> => {
    const { data, error, response } =
      await api(sessionToken()).GET('/v1/me/entitlement')
    if (response.status === 401) sessionRejected()
    if (!data)
      throw new Error(errorMessage(error, 'Aaru Plus could not be loaded.'))
    return data
  },
)
