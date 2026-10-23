import type { ComponentProps, ValidComponent } from 'solid-js'
import { Show, mergeProps, splitProps } from 'solid-js'
import { Dialog as DialogPrimitive } from '@kobalte/core/dialog'

import { cx } from '~/lib/cva'

export const DialogPortal = DialogPrimitive.Portal

export type DialogProps = ComponentProps<typeof DialogPrimitive>

export const Dialog = (props: DialogProps) => {
  return <DialogPrimitive data-slot="dialog" {...props} />
}

export type DialogTriggerProps<T extends ValidComponent = 'button'> =
  ComponentProps<typeof DialogPrimitive.Trigger<T>>

export const DialogTrigger = <T extends ValidComponent = 'button'>(
  props: DialogTriggerProps<T>,
) => {
  return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />
}

export type DialogCloseButtonProps<T extends ValidComponent = 'button'> =
  ComponentProps<typeof DialogPrimitive.CloseButton<T>>

export const DialogCloseButton = <T extends ValidComponent = 'button'>(
  props: DialogCloseButtonProps<T>,
) => {
  return <DialogPrimitive.CloseButton data-slot="dialog-close" {...props} />
}

/** Aaru: where the modal sits. `center` is shadcn's; `sheet` rises from the bottom edge on
 * phones and centres from `sm` up; `full` fills the viewport. */
const placements = {
  center: '',
  sheet:
    'max-sm:top-auto max-sm:bottom-0 max-sm:max-w-full max-sm:translate-y-0 max-sm:rounded-b-none max-sm:data-[expanded]:slide-in-from-bottom-6 max-sm:data-[closed]:slide-out-to-bottom-6 max-sm:data-[expanded]:zoom-in-100 max-sm:data-[closed]:zoom-out-100',
  full: 'inset-0 h-dvh max-h-none w-full max-w-none translate-x-0 translate-y-0 rounded-none sm:max-w-none data-[expanded]:zoom-in-100 data-[closed]:zoom-out-100',
} as const

export type DialogContentProps<T extends ValidComponent = 'div'> =
  ComponentProps<typeof DialogPrimitive.Content<T>> & {
    showCloseButton?: boolean
    placement?: keyof typeof placements
  }

export const DialogContent = <T extends ValidComponent = 'div'>(
  props: DialogContentProps<T>,
) => {
  const merge = mergeProps(
    {
      showCloseButton: true,
    } as DialogContentProps,
    props,
  )
  const [, rest] = splitProps(merge, [
    'class',
    'children',
    'showCloseButton',
    'placement',
  ])

  return (
    <>
      <DialogPrimitive.Overlay
        data-slot="dialog-overlay"
        class="data-[expanded]:animate-in data-[closed]:animate-out data-[closed]:fade-out-0 data-[expanded]:fade-in-0 fixed inset-0 z-50 bg-scrim"
      />
      <DialogPrimitive.Content
        data-slot="dialog-content"
        class={cx(
          // Aaru: paper, the card radius, no border, a deeper shadow, and never taller than
          // the viewport.
          'bg-background text-foreground data-[expanded]:animate-in data-[closed]:animate-out data-[closed]:fade-out-0 data-[expanded]:fade-in-0 data-[closed]:zoom-out-95 data-[expanded]:zoom-in-95 fixed top-[50%] left-[50%] z-50 grid max-h-[85dvh] w-full max-w-[calc(100%-2rem)] translate-x-[-50%] translate-y-[-50%] gap-4 overflow-y-auto rounded-card p-6 shadow-lift duration-200 sm:max-w-lg',
          placements[merge.placement ?? 'center'],
          props.class,
        )}
        {...rest}
        // Aaru: like the native <dialog>, focus starts on an `autofocus` element when there is
        // one (a search field), else Kobalte's first tabbable.
        onOpenAutoFocus={(event: Event) => {
          const own = merge.onOpenAutoFocus as
            ((event: Event) => void) | undefined
          own?.(event)
          if (event.defaultPrevented) return
          const target = (
            event.currentTarget as HTMLElement | null
          )?.querySelector<HTMLElement>('[autofocus]')
          if (target) {
            event.preventDefault()
            target.focus()
          }
        }}
      >
        {props.children}
        <Show when={props.showCloseButton}>
          <DialogPrimitive.CloseButton
            aria-label="Close"
            class="focus-visible:ring-ring absolute top-4 right-4 rounded-xs opacity-70 transition-[opacity,box-shadow] duration-200 hover:opacity-100 focus-visible:ring-2 focus-visible:outline-none [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path
                fill="none"
                stroke="currentColor"
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M18 6L6 18M6 6l12 12"
              />
            </svg>
          </DialogPrimitive.CloseButton>
        </Show>
      </DialogPrimitive.Content>
    </>
  )
}

export type DialogHeaderProps = ComponentProps<'div'>

export const DialogHeader = (props: DialogHeaderProps) => {
  const [, rest] = splitProps(props, ['class'])

  return (
    <div
      data-slot="dialog-header"
      class={cx('flex flex-col gap-2 text-center sm:text-left', props.class)}
      {...rest}
    />
  )
}

export type DialogFooterProps = ComponentProps<'div'>

export const DialogFooter = (props: DialogFooterProps) => {
  const [, rest] = splitProps(props, ['class'])

  return (
    <div
      data-slot="dialog-footer"
      class={cx(
        'flex flex-col-reverse gap-2 sm:flex-row sm:justify-end',
        props.class,
      )}
      {...rest}
    />
  )
}

export type DialogTitleProps<T extends ValidComponent = 'h2'> = ComponentProps<
  typeof DialogPrimitive.Title<T>
>

export const DialogTitle = <T extends ValidComponent = 'h2'>(
  props: DialogTitleProps<T>,
) => {
  const [, rest] = splitProps(props as DialogTitleProps, ['class'])

  return (
    <DialogPrimitive.Title
      data-slot="dialog-title"
      class={cx('font-display text-xl leading-tight font-medium', props.class)}
      {...rest}
    />
  )
}

export type DialogDescriptionProps<T extends ValidComponent = 'p'> =
  ComponentProps<typeof DialogPrimitive.Description<T>>

export const DialogDescription = <T extends ValidComponent = 'p'>(
  props: DialogDescriptionProps<T>,
) => {
  const [, rest] = splitProps(props as DialogDescriptionProps, ['class'])

  return (
    <DialogPrimitive.Description
      data-slot="dialog-description"
      class={cx('text-muted-foreground text-sm', props.class)}
      {...rest}
    />
  )
}
