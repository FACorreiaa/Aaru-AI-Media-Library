import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import type { components } from '../api/schema'
import { mediaRef } from '../groups/media-ref'
import { check, checkEmpty } from '../groups/responses'
import { sessionToken } from '../session/guard'
import type { SocialUser } from '../social/server'
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

/** One post, who upvoted it, its first comments, and the viewer's friends (for @-mentions). */
export const loadPost = createServerFn({ method: 'GET' })
  .validator(postRef)
  .handler(
    async ({
      data,
    }): Promise<{
      post: BoardPost
      upvoters: SocialUser[]
      comments: BoardCommentPage
      friends: SocialUser[]
    }> => {
      const client = api(sessionToken())
      const [post, upvoters, comments, friends] = await Promise.all([
        client.GET('/v1/board/posts/{postId}', postPath(data)),
        client.GET('/v1/board/posts/{postId}/upvotes', postPath(data)),
        client.GET('/v1/board/posts/{postId}/comments', postPath(data)),
        client.GET('/v1/social/friends'),
      ])
      const fallback = 'That post could not be loaded.'
      return {
        post: check(post, fallback),
        upvoters: check(upvoters, fallback).items,
        comments: check(comments, fallback),
        friends: check(friends, fallback).items,
      }
    },
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

/** Reports a post through the user-report route; the note says which post. */
export const reportPost = createServerFn({ method: 'POST' })
  .validator(
    z.object({
      authorId: uuid,
      postId: uuid,
      reason: z.enum(['spam', 'harassment', 'impersonation', 'other']),
    }),
  )
  .handler(async ({ data }) =>
    checkEmpty(
      await api(sessionToken()).POST('/v1/social/reports', {
        body: {
          userId: data.authorId,
          reason: data.reason,
          note: `post:${data.postId}`,
        },
      }),
      'That report was not sent.',
    ),
  )
