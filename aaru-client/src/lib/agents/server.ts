import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { errorMessage } from '../api/errors'
import { sessionRejected, sessionToken } from '../session/guard'
import type { components } from '../api/schema'
import { AGENT_KINDS } from './model'

// OUT-004 on the web: connect an MCP client (Claude Code, Codex, Hermes, Gemini CLI, any
// other) over the same `/v1/agent/tokens` routes as the Apple apps. The setup steps come from
// the server so both clients show the same ones.

export type AgentToken = components['schemas']['AgentToken']
export type AgentSetup = components['schemas']['AgentSetup']
export type AgentConnection = components['schemas']['AgentTokenCreated']

const kind = z.enum(AGENT_KINDS)

function check<T>(
  result: { data?: T; error?: unknown; response: Response },
  fallback: string,
): T {
  if (result.response.status === 401) sessionRejected()
  if (result.data === undefined)
    throw new Error(errorMessage(result.error, fallback))
  return result.data
}

/** The user's live MCP connections, newest first. */
export const listConnections = createServerFn({ method: 'GET' }).handler(
  async (): Promise<AgentToken[]> =>
    check(
      await api(sessionToken()).GET('/v1/agent/tokens', {
        params: { query: { for: 'mcp' } },
      }),
      'Your connections could not be loaded.',
    ).items,
)

/** One client's steps, with a placeholder where the token goes. */
export const getSetup = createServerFn({ method: 'GET' })
  .validator(z.object({ kind }))
  .handler(async ({ data }): Promise<AgentSetup> =>
    check(
      await api(sessionToken()).GET('/v1/agent/setup/{kind}', {
        params: { path: { kind: data.kind } },
      }),
      'The setup could not be loaded.',
    ),
  )

/** Mints a token. The answer carries the steps with the token filled in; shown once. */
export const createConnection = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      kind,
      name: z.string().max(80).optional(),
      allowLibraryWrites: z.boolean(),
    }),
  )
  .handler(async ({ data }): Promise<AgentConnection> =>
    check(
      await api(sessionToken()).POST('/v1/agent/tokens', {
        body: {
          kind: data.kind,
          name: data.name?.trim() || undefined,
          allowLibraryWrites: data.allowLibraryWrites,
        },
      }),
      'The connection could not be created.',
    ),
  )

export const revokeConnection = createServerFn({ method: 'POST' })
  .validator(z.object({ id: z.string().uuid() }))
  .handler(async ({ data }) => {
    const result = await api(sessionToken()).DELETE('/v1/agent/tokens/{id}', {
      params: { path: { id: data.id } },
    })
    if (result.response.status === 401) sessionRejected()
    if (!result.response.ok)
      throw new Error(
        errorMessage(result.error, 'That connection was not revoked.'),
      )
  })
