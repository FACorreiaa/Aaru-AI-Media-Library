import { splitProps, type ComponentProps, type ValidComponent } from 'solid-js'
import { Image as ImagePrimitive } from '@kobalte/core/image'

import { cx } from '~/lib/cva'

// shadcn-solid's Avatar on Kobalte's Image (SOC-001b). Aaru's look is the medallion disc under
// the photo, with the fallback (a monogram) on it until the photo loads, or when there is none.

export type AvatarProps<T extends ValidComponent = 'span'> = ComponentProps<
  typeof ImagePrimitive<T>
>

export const Avatar = <T extends ValidComponent = 'span'>(
  props: AvatarProps<T>,
) => {
  const [, rest] = splitProps(props as AvatarProps, ['class'])

  return (
    <ImagePrimitive
      data-slot="avatar"
      class={cx(
        'relative flex size-10 shrink-0 overflow-hidden rounded-full bg-medallion',
        props.class,
      )}
      {...rest}
    />
  )
}

export type AvatarImageProps<T extends ValidComponent = 'img'> = ComponentProps<
  typeof ImagePrimitive.Img<T>
>

export const AvatarImage = <T extends ValidComponent = 'img'>(
  props: AvatarImageProps<T>,
) => {
  const [, rest] = splitProps(props as AvatarImageProps, ['class'])

  return (
    <ImagePrimitive.Img
      data-slot="avatar-image"
      class={cx('aspect-square size-full object-cover', props.class)}
      {...rest}
    />
  )
}

export type AvatarFallbackProps<T extends ValidComponent = 'span'> =
  ComponentProps<typeof ImagePrimitive.Fallback<T>>

export const AvatarFallback = <T extends ValidComponent = 'span'>(
  props: AvatarFallbackProps<T>,
) => {
  const [, rest] = splitProps(props as AvatarFallbackProps, ['class'])

  return (
    <ImagePrimitive.Fallback
      data-slot="avatar-fallback"
      class={cx(
        'flex size-full items-center justify-center rounded-full',
        props.class,
      )}
      {...rest}
    />
  )
}
