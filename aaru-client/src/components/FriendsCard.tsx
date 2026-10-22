import { Link } from '@tanstack/solid-router'
import { Show, createSignal } from 'solid-js'
import { saveSocialSettings } from '../lib/social/server'
import { Switch } from './ui/switch'

// Settings → Account: your handle, the way to Friends, and whether friends see your library
// (SOC-001). Strangers never see anything, whatever this says.
export function FriendsCard(props: {
  handle?: string
  shareLibraryWithFriends: boolean
}) {
  const [sharing, setSharing] = createSignal(props.shareLibraryWithFriends)
  const [problem, setProblem] = createSignal<string | null>(null)

  async function change(next: boolean) {
    setSharing(next)
    setProblem(null)
    try {
      await saveSocialSettings({ data: { shareLibraryWithFriends: next } })
    } catch (error) {
      setSharing(!next)
      setProblem(error instanceof Error ? error.message : 'That was not saved.')
    }
  }

  return (
    <section
      id="profile"
      class="mt-10 scroll-mt-6 rounded-[20px] bg-surface p-5"
    >
      <h2 class="font-display text-xl font-medium">Profile and friends</h2>
      <p class="mt-2 text-sm">
        <Show
          when={props.handle}
          fallback={<span class="text-muted">No handle yet.</span>}
        >
          {(handle) => (
            <>
              <span class="text-muted">Your handle</span>{' '}
              <span class="font-medium">@{handle()}</span>
            </>
          )}
        </Show>{' '}
        <Link
          to="/app/friends"
          class="font-semibold text-accent hover:underline"
        >
          Friends, invites and requests
        </Link>
      </p>
      <Switch
        class="mt-4"
        checked={sharing()}
        onChange={(next) => void change(next)}
        label="Show my library to friends"
        description="Friends see what you’re watching, what you finished and what you share. Nobody else ever does."
      />
      <Show when={problem()}>
        {(message) => (
          <p role="alert" class="mt-3 text-sm text-danger">
            {message()}
          </p>
        )}
      </Show>
    </section>
  )
}
