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

/** The user's live MCP and browser-extension connections, newest first. */
export const listConnections = createServerFn({ method: 'GET' }).handler(
  async (): Promise<AgentToken[]> => {
    const client = api(sessionToken())
    const [mcp, browsers] = await Promise.all(
      (['mcp', 'scrobble'] as const).map(async (group) =>
        check(
          await client.GET('/v1/agent/tokens', {
            params: { query: { for: group } },
          }),
          'Your connections could not be loaded.',
        ),
      ),
    )
    return [...mcp.items, ...browsers.items].sort((a, b) =>
      b.createdAt.localeCompare(a.createdAt),
    )
  },
)

/**
 * SCR-007: a token for this browser's Aaru extension, which can only scrobble. The connect page
 * hands the secret straight to the extension; it is never shown.
 */
export const connectExtension = createServerFn({ method: 'POST' })
  .validator(z.object({ name: z.string().max(80).optional() }))
  .handler(async ({ data }): Promise<{ id: string; secret: string }> => {
    const created = check(
      await api(sessionToken()).POST('/v1/agent/tokens', {
        body: { kind: 'browser', name: data.name?.trim() || undefined },
      }),
      'This browser could not be connected.',
    )
    return { id: created.token.id, secret: created.secret }
  })

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
      allowImports: z.boolean(),
    }),
  )
  .handler(async ({ data }): Promise<AgentConnection> =>
    check(
      await api(sessionToken()).POST('/v1/agent/tokens', {
        body: {
          kind: data.kind,
          name: data.name?.trim() || undefined,
          allowLibraryWrites: data.allowLibraryWrites,
          allowImports: data.allowImports,
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
