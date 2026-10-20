import { createFileRoute, useNavigate } from '@tanstack/solid-router'
import { onMount } from 'solid-js'
import { useGroup } from '../components/groups/shell'

// A group with no channel picked. On a phone the channel list (beside this) is the page; on a
// tablet or desktop there is always a channel open, so this goes to the group's #general.
export const Route = createFileRoute('/app_/groups/$groupId/')({
  component: PickChannel,
})

function PickChannel() {
  const scope = useGroup()
  const navigate = useNavigate()
  onMount(() => {
    if (window.matchMedia('(min-width: 768px)').matches)
      void navigate({
        to: '/app/groups/$groupId/$channelId',
        params: {
          groupId: scope.detail().group.id,
          channelId: scope.detail().group.defaultChannelId,
        },
        replace: true,
      })
  })
  return <div class="hidden flex-1 md:block" />
}
