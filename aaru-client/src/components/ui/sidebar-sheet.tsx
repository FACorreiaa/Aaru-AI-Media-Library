import type { JSX } from 'solid-js'
import { Drawer, DrawerContent } from './drawer'

/**
 * Aaru: the sidebar as a sheet below 1024px. Its own module so `Sidebar` can load it lazily:
 * corvu's drawer (~12 KB gz) stays out of a wide screen's first load and arrives as soon as the
 * viewport is narrow, before anyone can tap the menu.
 */
export default function SidebarSheet(props: {
  open: boolean
  onOpenChange: (open: boolean) => void
  side?: 'left' | 'right'
  width: string
  children: JSX.Element
}) {
  return (
    <Drawer
      open={props.open}
      onOpenChange={props.onOpenChange}
      side={props.side}
    >
      <DrawerContent
        data-sidebar="sidebar"
        data-slot="sidebar"
        data-mobile="true"
        class="bg-sidebar text-sidebar-foreground w-(--sidebar-width) p-0 [&>button]:hidden"
        style={{
          '--sidebar-width': props.width,
        }}
      >
        <div class="flex h-full w-full flex-col">{props.children}</div>
      </DrawerContent>
    </Drawer>
  )
}
