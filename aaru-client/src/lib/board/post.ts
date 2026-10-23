import { createServerFn } from '@tanstack/solid-start'
import { z } from 'zod'
import { api } from '../api/client'
import { check } from '../groups/responses'
import { sessionToken } from '../session/guard'
import type { SocialUser } from '../social/server'
import type { BoardPost } from './model'
import type { BoardCommentPage } from './server'

// The post page's loader on its own (BOARD-002): the route tree loads every route's loader
// with the first page, so this keeps the Board's other calls out of every page's first load.

/** The post page's first load. */
export type PostPage = {
  post: BoardPost
  upvoters: SocialUser[]
  comments: BoardCommentPage
  friends: SocialUser[]
  me: SocialUser
}

/**
 * One post, who upvoted it, its first comments, the viewer's friends (for @-mentions) and the
 * viewer. `null` when the post is not there for you (deleted, unfriended, blocked: the server
 * answers 404 to all three); any other failure throws.
 */
export const loadPost = createServerFn({ method: 'GET' })
  .validator(z.object({ postId: z.string().uuid() }))
  .handler(async ({ data }): Promise<PostPage | null> => {
    const client = api(sessionToken())
    const path = { params: { path: { postId: data.postId } } }
    const [post, upvoters, comments, friends, me] = await Promise.all([
      client.GET('/v1/board/posts/{postId}', path),
      client.GET('/v1/board/posts/{postId}/upvotes', path),
      client.GET('/v1/board/posts/{postId}/comments', path),
      client.GET('/v1/social/friends'),
      client.GET('/v1/me'),
    ])
    const fallback = 'That post could not be loaded.'
    const mine = check(me, fallback)
    if (post.response.status === 404) return null
    return {
      post: check(post, fallback),
      upvoters: check(upvoters, fallback).items,
      comments: check(comments, fallback),
      friends: check(friends, fallback).items,
      me: {
        userId: mine.userId,
        handle: mine.handle ?? 'you',
        displayName: mine.displayName,
      },
    }
  })
