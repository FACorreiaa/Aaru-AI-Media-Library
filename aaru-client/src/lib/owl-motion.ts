// How the 3D owl moves (BRD-011). The numbers are `design/owl-motion.json`, copied beside the
// scene so the bundle carries them; this module only turns a time into values. It imports no
// renderer: `owl3d/scene.ts` applies what it returns, and `OwlMotion.swift` is the same
// arithmetic for the Apple apps. A change here is a change there, and both tests hold the same
// expected values.
import data from './owl3d/owl-motion.json'
import rig from './owl3d/owl-rig.json'

export type Easing = 'sine' | 'linear'

export interface Keyframe {
  /** Fraction of the track's period, 0 to 1. */
  t: number
  v: number
}

export interface Track {
  /** The joint the value moves, or the material it lights. One of the two. */
  joint?: string
  material?: string
  property:
    | 'translateY'
    | 'rotateXDegrees'
    | 'rotateYDegrees'
    | 'rotateZDegrees'
    | 'emissiveScale'
  periodSeconds: number
  easing: Easing
  keyframes: Array<Keyframe>
}

export interface Blink {
  joints: Array<string>
  open: number
  shut: number
  intervalSeconds: [number, number]
  closeSeconds: number
  holdSeconds: number
  openSeconds: number
}

export interface LookAt {
  headYawDegrees: number
  headPitchDegrees: number
  pupilOffset: number
  timeConstantSeconds: number
}

export interface Look {
  headYawDegrees: number
  headPitchDegrees: number
  pupilX: number
  pupilY: number
}

export const STANDING = data.states.standing.tracks as Array<Track>
export const BLINK = data.blink as Blink
export const LOOK_AT: LookAt = data.lookAt
/** The poster's stance: degrees added to a joint's rest, by joint name. */
export const POSTER_POSE: Record<
  string,
  { rotateYDegrees?: number; rotateZDegrees?: number }
> = rig.posterPose

/** 0 to 1 along one span between two keyframes. */
export function ease(easing: Easing, u: number): number {
  return easing === 'sine' ? 0.5 - 0.5 * Math.cos(Math.PI * u) : u
}

/** A looping track's value at `seconds`. */
export function sampleTrack(track: Track, seconds: number): number {
  const frames = track.keyframes
  const phase =
    (((seconds % track.periodSeconds) + track.periodSeconds) %
      track.periodSeconds) /
    track.periodSeconds
  for (let i = 1; i < frames.length; i++) {
    const from = frames[i - 1]
    const to = frames[i]
    if (phase <= to.t) {
      const span = to.t - from.t
      const u = span > 0 ? (phase - from.t) / span : 1
      return from.v + (to.v - from.v) * ease(track.easing, u)
    }
  }
  return frames[frames.length - 1].v
}

/** The lids' scale `sinceStart` seconds into a blink: shut, held, open again. */
export function blinkScale(blink: Blink, sinceStart: number): number {
  const range = blink.shut - blink.open
  if (sinceStart < 0) return blink.open
  if (sinceStart < blink.closeSeconds) {
    return blink.open + range * ease('sine', sinceStart / blink.closeSeconds)
  }
  const held = sinceStart - blink.closeSeconds
  if (held < blink.holdSeconds) return blink.shut
  const opening = held - blink.holdSeconds
  if (opening < blink.openSeconds) {
    return blink.shut - range * ease('sine', opening / blink.openSeconds)
  }
  return blink.open
}

/** How long a whole blink takes. */
export function blinkSeconds(blink: Blink): number {
  return blink.closeSeconds + blink.holdSeconds + blink.openSeconds
}

/** The wait before the next blink, from a random number in 0…1. */
export function blinkWait(blink: Blink, random: number): number {
  const [least, most] = blink.intervalSeconds
  return least + (most - least) * random
}

/** Where the owl looks for a point at (`x`, `y`): each from -1 to 1 across the page, right and
 * up positive, and held inside that range. Turning the head toward +X is a positive yaw;
 * looking up is a negative pitch (a turn about X tips the face down). */
export function lookToward(lookAt: LookAt, x: number, y: number): Look {
  const cx = Math.max(-1, Math.min(1, x))
  const cy = Math.max(-1, Math.min(1, y))
  return {
    headYawDegrees: cx * lookAt.headYawDegrees,
    headPitchDegrees: -cy * lookAt.headPitchDegrees,
    pupilX: cx * lookAt.pupilOffset,
    pupilY: cy * lookAt.pupilOffset,
  }
}

/** One frame's step from `current` toward `target`: quick at first, never past it. */
export function approach(
  current: number,
  target: number,
  deltaSeconds: number,
  timeConstantSeconds: number,
): number {
  if (timeConstantSeconds <= 0) return target
  return (
    current +
    (target - current) * (1 - Math.exp(-deltaSeconds / timeConstantSeconds))
  )
}
