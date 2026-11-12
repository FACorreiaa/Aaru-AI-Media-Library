import { describe, expect, it } from 'vitest'
import {
  BLINK,
  LOOK_AT,
  POSTER_POSE,
  STANDING,
  approach,
  blinkScale,
  blinkSeconds,
  blinkWait,
  lookToward,
  sampleTrack,
} from './owl-motion'

// The same expected values are in aaru-ios/AaruTests/OwlMotionTests.swift: the web and the
// Apple owl must move alike.

function track(target: string, property: string) {
  const found = STANDING.find(
    (t) => (t.joint ?? t.material) === target && t.property === property,
  )
  if (!found) throw new Error(`no ${target} ${property} track`)
  return found
}

describe('sampleTrack', () => {
  it('breathes: the body is halfway up a quarter into its period', () => {
    const breath = track('Body', 'translateY')
    expect(sampleTrack(breath, 0)).toBeCloseTo(0, 6)
    expect(sampleTrack(breath, 1.125)).toBeCloseTo(0.006, 6)
    expect(sampleTrack(breath, 2.25)).toBeCloseTo(0.012, 6)
  })

  it('loops', () => {
    const breath = track('Body', 'translateY')
    expect(sampleTrack(breath, 4.5 + 1.125)).toBeCloseTo(0.006, 6)
    expect(sampleTrack(breath, -3.375)).toBeCloseTo(0.006, 6)
  })

  it('drifts the head between uneven keyframes', () => {
    const yaw = track('Head', 'rotateYDegrees')
    expect(sampleTrack(yaw, 1.65)).toBeCloseTo(1.25, 6)
    expect(sampleTrack(yaw, 5.5)).toBeCloseTo(0.25, 6)
    expect(sampleTrack(yaw, 9.35)).toBeCloseTo(-1, 6)
  })

  it('pulses the amber light around its rest', () => {
    const glow = track('amber', 'emissiveScale')
    expect(sampleTrack(glow, 0)).toBeCloseTo(0.85, 6)
    expect(sampleTrack(glow, 2)).toBeCloseTo(1.2, 6)
  })
})

describe('blink', () => {
  it('shuts, holds and opens', () => {
    expect(blinkScale(BLINK, -1)).toBe(0.001)
    expect(blinkScale(BLINK, 0.04)).toBeCloseTo(0.5005, 6)
    expect(blinkScale(BLINK, 0.1)).toBe(1)
    expect(blinkScale(BLINK, 0.2)).toBeCloseTo(0.5005, 6)
    expect(blinkScale(BLINK, 0.3)).toBe(0.001)
    expect(blinkSeconds(BLINK)).toBeCloseTo(0.27, 6)
  })

  it('waits four to seven seconds', () => {
    expect(blinkWait(BLINK, 0)).toBe(4)
    expect(blinkWait(BLINK, 0.5)).toBe(5.5)
    expect(blinkWait(BLINK, 1)).toBe(7)
  })
})

describe('look', () => {
  it('turns toward the point and stops at its limits', () => {
    const look = lookToward(LOOK_AT, 2, -0.5)
    expect(look.headYawDegrees).toBe(14)
    expect(look.headPitchDegrees).toBe(4)
    expect(look.pupilX).toBeCloseTo(0.02, 6)
    expect(look.pupilY).toBeCloseTo(-0.01, 6)
  })

  it('eases toward its target and never passes it', () => {
    expect(approach(0, 1, 0.18, 0.18)).toBeCloseTo(0.632121, 6)
    expect(approach(0, 1, 100, 0.18)).toBeCloseTo(1, 6)
    expect(approach(0.4, 1, 0.016, 0)).toBe(1)
  })
})

describe('poster pose', () => {
  it('is the rig file’s', () => {
    expect(POSTER_POSE.Owl).toEqual({ rotateYDegrees: -32 })
    expect(POSTER_POSE.Head).toEqual({ rotateYDegrees: 24, rotateZDegrees: -6 })
  })
})
