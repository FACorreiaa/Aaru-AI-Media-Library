import { createSignal } from 'solid-js'
import { toast } from '~/components/ui'
import { inviterName } from '../lib/social/model'
import { blockUser } from '../lib/social/server'
import type { SocialUser } from '../lib/social/server'
import { ConfirmDialog } from './ConfirmDialog'

/**
 * Asks before blocking the author of a post, a comment or a group message, in the words a
 * friend's profile uses, then blocks. The person is not told. `onBlocked` runs once the block is
 * saved; the owner closes the dialog and shows what changed.
 */
export function BlockDialog(props: {
  open: boolean
  person: SocialUser
  onBlocked: (person: SocialUser) => void
  onClose: () => void
}) {
  const [blocking, setBlocking] = createSignal(false)

  async function block() {
    if (blocking()) return
    const person = props.person
    setBlocking(true)
    try {
      await blockUser({ data: { userId: person.userId } })
      props.onBlocked(person)
    } catch (error) {
      toast(
        error instanceof Error ? error.message : 'That person was not blocked.',
      )
    } finally {
      setBlocking(false)
    }
  }

  return (
    <ConfirmDialog
      open={props.open}
      title={`Block ${inviterName(props.person)}?`}
      description="They are removed from your friends and can’t see your library. You can unblock them in Settings."
      confirmLabel={blocking() ? 'Blocking…' : 'Block'}
      busy={blocking()}
      onConfirm={() => void block()}
      onCancel={() => {
        if (!blocking()) props.onClose()
      }}
    />
  )
}
