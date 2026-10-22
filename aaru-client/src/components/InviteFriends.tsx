import { For, Show, createResource, createSignal } from 'solid-js'
import { kindOf } from '../lib/library/model'
import type { CatalogHit } from '../lib/library/model'
import { searchCatalog } from '../lib/library/server'
import { inviteExpiry, invitePlea } from '../lib/social/model'
import { createInvite, loadInvites, revokeInvite } from '../lib/social/server'
import type { FriendInvite } from '../lib/social/server'
import { Poster } from './Poster'
import { Button } from './ui/button'

// SOC-002: one-use invite links. Each link befriends the first person who opens it, within two
// weeks. A link may carry one title ("Watch Arrival with me"), picked from the catalog.
export function InviteFriends() {
  const [invites, { refetch }] = createResource(() => loadInvites())
  const [query, setQuery] = createSignal('')
  const [hits, setHits] = createSignal<CatalogHit[]>([])
  const [title, setTitle] = createSignal<CatalogHit | null>(null)
  const [busy, setBusy] = createSignal(false)
  const [notice, setNotice] = createSignal<string | null>(null)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function run(action: () => Promise<void>, fallback: string) {
    setBusy(true)
    setProblem(null)
    setNotice(null)
    try {
      await action()
    } catch (error) {
      setProblem(error instanceof Error ? error.message : fallback)
    } finally {
      setBusy(false)
    }
  }

  function search(event: SubmitEvent) {
    event.preventDefault()
    if (query().trim().length < 2) return
    void run(async () => {
      const results = await searchCatalog({
        data: { q: query().trim(), type: 'all' },
      })
      setHits(results.items.slice(0, 5))
    }, 'Search is not available right now.')
  }

  /** The share sheet where there is one (phones), else the clipboard. */
  async function share(invite: FriendInvite) {
    const text = invite.title
      ? invitePlea(
          invite.title.title,
          kindOf(invite.title.type, invite.title.isAnime),
        )
      : 'Join me on Aaru.'
    if (typeof navigator.share === 'function') {
      try {
        await navigator.share({ title: 'Aaru', text, url: invite.url })
        return
      } catch (error) {
        if (error instanceof DOMException && error.name === 'AbortError') return
      }
    }
    await navigator.clipboard.writeText(invite.url)
    setNotice('Link copied. It works once, for the first person who opens it.')
  }

  function make() {
    void run(async () => {
      const picked = title()
      const invite = await createInvite({
        data: {
          title: picked
            ? {
                type: picked.type,
                ids: picked.ids,
                title: picked.title,
                year: picked.year,
              }
            : undefined,
        },
      })
      setTitle(null)
      setHits([])
      setQuery('')
      await refetch()
      await share(invite)
    }, 'The invite was not made.')
  }

  return (
    <div class="mt-6 rounded-[16px] bg-paper p-4">
      <h3 class="font-display text-lg font-medium">Invite a friend</h3>
      <p class="mt-1 max-w-[60ch] text-sm text-muted">
        A link that works once, for two weeks. Whoever opens it joins Aaru (or
        signs in) and you’re friends.
      </p>

      <Show
        when={title()}
        fallback={
          <form class="mt-4 flex flex-wrap items-end gap-2" onSubmit={search}>
            <label class="flex flex-col gap-1 text-sm">
              <span class="font-medium">
                Something to watch together{' '}
                <span class="font-normal text-muted">(optional)</span>
              </span>
              <input
                type="search"
                class="min-h-11 w-64 max-w-full rounded-[14px] border border-line bg-surface px-3 outline-none focus:ring-2 focus:ring-accent"
                placeholder="A film, show or book"
                value={query()}
                onInput={(event) => setQuery(event.currentTarget.value)}
              />
            </label>
            <Button
              type="submit"
              variant="quiet"
              disabled={busy() || query().trim().length < 2}
            >
              Find
            </Button>
          </form>
        }
      >
        {(picked) => (
          <div class="mt-4 flex items-center gap-3">
            <Poster
              url={picked().posterUrl}
              kind={kindOf(picked().type, picked().isAnime)}
              radius="thumb"
              class="w-10 shrink-0"
            />
            <p class="min-w-0 flex-1 font-display text-base italic">
              “
              {invitePlea(
                picked().title,
                kindOf(picked().type, picked().isAnime),
              )}
              ”
            </p>
            <Button variant="ghost" size="sm" onClick={() => setTitle(null)}>
              Remove
            </Button>
          </div>
        )}
      </Show>

      <Show when={!title() && hits().length > 0}>
        <ul class="mt-3 divide-y divide-line">
          <For each={hits()}>
            {(hit) => (
              <li>
                <button
                  type="button"
                  class="flex min-h-12 w-full items-center gap-3 py-2 text-left text-sm hover:bg-surface"
                  onClick={() => setTitle(hit)}
                >
                  <Poster
                    url={hit.posterUrl}
                    kind={kindOf(hit.type, hit.isAnime)}
                    radius="thumb"
                    class="w-8 shrink-0"
                  />
                  <span class="min-w-0 truncate font-medium">{hit.title}</span>
                  <Show when={hit.year}>
                    <span class="text-muted">{hit.year}</span>
                  </Show>
                </button>
              </li>
            )}
          </For>
        </ul>
      </Show>

      <Button variant="primary" class="mt-4" disabled={busy()} onClick={make}>
        {busy() ? 'Making link…' : 'Make an invite link'}
      </Button>

      <Show when={notice()}>
        {(message) => (
          <p role="status" class="mt-3 text-sm">
            {message()}
          </p>
        )}
      </Show>
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>

      <Show when={(invites() ?? []).length > 0}>
        <h4 class="mt-6 text-sm font-semibold">
          Waiting to be opened ({invites()?.length})
        </h4>
        <ul class="mt-1 divide-y divide-line">
          <For each={invites()}>
            {(invite) => (
              <li class="flex flex-wrap items-center justify-between gap-3 py-3">
                <span class="min-w-0 text-sm">
                  <span class="block truncate font-medium">
                    {invite.title
                      ? invitePlea(
                          invite.title.title,
                          kindOf(invite.title.type, invite.title.isAnime),
                        )
                      : 'Friend invite'}
                  </span>
                  <span class="text-muted">
                    {inviteExpiry(invite.expiresAt)}
                  </span>
                </span>
                <span class="flex items-center gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => void share(invite)}
                  >
                    Share
                  </Button>
                  <Button
                    variant="danger-outline"
                    size="sm"
                    disabled={busy()}
                    onClick={() =>
                      void run(async () => {
                        await revokeInvite({ data: { code: invite.code } })
                        await refetch()
                      }, 'That invite is already gone.')
                    }
                  >
                    Revoke
                  </Button>
                </span>
              </li>
            )}
          </For>
        </ul>
      </Show>
    </div>
  )
}
