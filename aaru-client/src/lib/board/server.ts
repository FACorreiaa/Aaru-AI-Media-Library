import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import type { components } from '../api/schema'
import { mediaRef } from '../groups/media-ref'
import { check, checkEmpty } from '../groups/responses'
import { sessionToken } from '../session/guard'
import type { BoardComment, BoardPost } from './model'

// BOARD-002 on the web: the calls behind the friends-only Board. Every rule about who sees what
// is the server's; these forward the session and nothing else.

export type BoardCommentPage = components['schemas']['BoardCommentPage']

const uuid = z.string().uuid()
const postRef = z.object({ postId: uuid })
const postPath = (data: { postId: string }) => ({
  params: { path: { postId: data.postId } },
})

/** The Board's first or next page, with how many friends the viewer has and who they are. */
export const loadBoard = createServerFn({ method: 'GET' })
  .validator(
    z.object({
      sort: z.enum(['recent', 'top']),
      before: z.string().optional(),
    }),
  )
  .handler(
    async ({
      data,
    }): Promise<{
      posts: BoardPost[]
      friendCount: number
      me: { id: string; handle?: string }
    }> => {
      const client = api(sessionToken())
      const [board, friends, me] = await Promise.all([
        client.GET('/v1/board', {
          params: { query: { sort: data.sort, before: data.before } },
        }),
        client.GET('/v1/social/friends'),
        client.GET('/v1/me'),
      ])
      const fallback = 'The Board could not be loaded.'
      const mine = check(me, fallback)
      return {
        posts: check(board, fallback).items,
        friendCount: check(friends, fallback).items.length,
        me: { id: mine.userId, handle: mine.handle },
      }
    },
  )

export const createPost = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      body: z.string(),
      title: mediaRef.optional(),
      rating: z.number().int().optional(),
      spoiler: z
        .object({
          season: z.number().int().optional(),
          episode: z.number().int().optional(),
          ending: z.boolean().optional(),
        })
        .optional(),
      spoilerFree: z.boolean().optional(),
    }),
  )
  .handler(async ({ data }): Promise<BoardPost> =>
    check(
      await api(sessionToken()).POST('/v1/board/posts', { body: data }),
      'Your post was not shared.',
    ),
  )

export const editPost = createServerFn({ method: 'POST' })
  .validator(z.object({ postId: uuid, body: z.string() }))
  .handler(async ({ data }): Promise<BoardPost> =>
    check(
      await api(sessionToken()).PATCH('/v1/board/posts/{postId}', {
        ...postPath(data),
        body: { body: data.body },
      }),
      'Your edit was not saved.',
    ),
  )

export const deletePost = createServerFn({ method: 'POST' })
  .validator(postRef)
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE(
        '/v1/board/posts/{postId}',
        postPath(data),
      ),
      'That post was not deleted.',
    ),
  )

export const setUpvote = createServerFn({ method: 'POST' })
  .validator(z.object({ postId: uuid, on: z.boolean() }))
  .handler(async ({ data }) => {
    const client = api(sessionToken())
    const fallback = 'Your upvote was not saved.'
    checkEmpty(
      data.on
        ? await client.PUT('/v1/board/posts/{postId}/upvote', postPath(data))
        : await client.DELETE(
            '/v1/board/posts/{postId}/upvote',
            postPath(data),
          ),
      fallback,
    )
  })

export const loadComments = createServerFn({ method: 'GET' })
  .validator(z.object({ postId: uuid, after: uuid.optional() }))
  .handler(async ({ data }): Promise<BoardCommentPage> =>
    check(
      await api(sessionToken()).GET('/v1/board/posts/{postId}/comments', {
        params: { path: { postId: data.postId }, query: { after: data.after } },
      }),
      'The comments could not be loaded.',
    ),
  )

export const addComment = createServerFn({ method: 'POST' })
  .validator(
    z.object({ postId: uuid, body: z.string(), replyTo: uuid.optional() }),
  )
  .handler(async ({ data }): Promise<BoardComment> =>
    check(
      await api(sessionToken()).POST('/v1/board/posts/{postId}/comments', {
        ...postPath(data),
        body: { body: data.body, replyTo: data.replyTo },
      }),
      'Your comment was not posted.',
    ),
  )

export const deleteComment = createServerFn({ method: 'POST' })
  .validator(z.object({ postId: uuid, commentId: uuid }))
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).DELETE(
        '/v1/board/posts/{postId}/comments/{commentId}',
        {
          params: { path: { postId: data.postId, commentId: data.commentId } },
        },
      ),
      'That comment was not deleted.',
    ),
  )

/** The posts about one title, for its page. */
export const listTitlePosts = createServerFn({ method: 'GET' })
  .validator(z.object({ titleId: uuid }))
  .handler(
    async ({ data }): Promise<BoardPost[]> =>
      check(
        await api(sessionToken()).GET('/v1/titles/{id}/posts', {
          params: { path: { id: data.titleId } },
        }),
        'The posts about this title could not be loaded.',
      ).items,
  )

/** What a title page's "From friends" needs: a few posts, and whether there is anyone to hear from. */
export const loadFromFriends = createServerFn({ method: 'GET' })
  .validator(z.object({ titleId: uuid }))
  .handler(
    async ({
      data,
    }): Promise<{
      posts: BoardPost[]
      friendHandles: string[]
      myHandle?: string
    }> => {
      const client = api(sessionToken())
      const [posts, friends, me] = await Promise.all([
        client.GET('/v1/titles/{id}/posts', {
          params: { path: { id: data.titleId } },
        }),
        client.GET('/v1/social/friends'),
        client.GET('/v1/me'),
      ])
      const fallback = 'The posts about this title could not be loaded.'
      return {
        posts: check(posts, fallback).items,
        friendHandles: check(friends, fallback).items.map((f) => f.handle),
        myHandle: check(me, fallback).handle,
      }
    },
  )

/** How long a report's own note may be: the server's 1,000 less the post reference. */
export const REPORT_NOTE_LENGTH = 900

/** Reports a post through the user-report route; the note says which post, then the reporter's words. */
export const reportPost = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      authorId: uuid,
      postId: uuid,
      reason: z.enum(['spam', 'harassment', 'impersonation', 'other']),
      /** What the reporter adds; the server keeps notes under 1,000 characters in all. */
      note: z.string().max(REPORT_NOTE_LENGTH).optional(),
    }),
  )
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST('/v1/social/reports', {
        body: {
          userId: data.authorId,
          reason: data.reason,
          note: [`post:${data.postId}`, data.note?.trim()]
            .filter(Boolean)
            .join('\n'),
        },
      }),
      'That report was not sent.',
    ),
  )

/** A title the composer starts with: enough to show it, send it, and word what posting does. */
export type ComposerTitle = {
  titleId: string
  type: components['schemas']['MediaType']
  title: string
  year?: number
  posterUrl?: string
  isAnime: boolean
  libraryItemId?: string
}

/**
 * The title a "Write about this" link names (`/app/friends?title=<id>`). The id is the one
 * `/app/title/$id` uses, a library item, so the composer knows the title is yours and says its
 * status stays; a catalog title id works too, read from the catalog.
 */
export const loadComposerTitle = createServerFn({ method: 'GET' })
  .validator(z.object({ id: uuid }))
  .handler(async ({ data }): Promise<ComposerTitle> => {
    const client = api(sessionToken())
    const fallback = 'That title could not be loaded.'
    const item = await client.GET('/v1/library/items/{id}', {
      params: { path: { id: data.id } },
    })
    if (item.response.status !== 404) {
      const entry = check(item, fallback)
      const t = entry.title
      return {
        titleId: t.id,
        type: t.type,
        title: t.title,
        year: t.year,
        posterUrl: t.posterUrl,
        isAnime: t.isAnime,
        libraryItemId: entry.id,
      }
    }
    const t = check(
      await client.GET('/v1/titles/{id}', {
        params: { path: { id: data.id } },
      }),
      fallback,
    )
    return {
      titleId: t.id,
      type: t.type,
      title: t.title,
      year: t.year,
      posterUrl: t.posterUrl,
      isAnime: t.isAnime,
    }
  })
