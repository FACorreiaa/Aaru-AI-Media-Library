import { describe, expect, it } from 'vitest'
import { SilenceDetector, levelOf, spokenText } from './silence'

function run(segments: Array<[number, number]>) {
  const detector = new SilenceDetector()
  let step = 0
  for (const [power, seconds] of segments) {
    for (let i = 0; i < Math.round(seconds * 10); i++) {
      const time = step / 10
      const stop = detector.feed(power, time)
      if (stop) return { stop, time }
      step++
    }
  }
  return { stop: null, time: step / 10 }
}

describe('silence detector', () => {
  it('stops about a second and a half after speech', () => {
    const result = run([
      [-60, 1],
      [-20, 2],
      [-60, 3],
    ])
    expect(result.stop).toBe('silence')
    expect(Math.abs(result.time - 4.5)).toBeLessThanOrEqual(0.1)
  })

  it('gives up with no speech, and caps at a minute', () => {
    expect(run([[-60, 10]]).stop).toBe('noSpeech')
    expect(
      run([
        [-60, 1],
        [-20, 70],
      ]).stop,
    ).toBe('cap')
  })

  it('reads a level in dBFS', () => {
    expect(levelOf(new Float32Array([1, -1]))).toBeCloseTo(0)
    expect(levelOf(new Float32Array(4))).toBe(-160)
  })

  it('turns markdown into words to read', () => {
    expect(
      spokenText('**Dune** by [Frank Herbert](https://x.test)\n- *one*\n'),
    ).toBe('Dune by Frank Herbert\none')
  })
})

describe('read-aloud voice', () => {
  it('takes only an on-device voice for the language', async () => {
    const { localVoice } = await import('./voice')
    const v = (lang: string, localService: boolean, isDefault = false) =>
      ({ lang, localService, default: isDefault }) as SpeechSynthesisVoice
    const voices = [v('en-US', false, true), v('pt-PT', true), v('en-GB', true)]
    expect(localVoice(voices, 'en')?.lang).toBe('en-GB')
    expect(localVoice(voices, 'pt')?.lang).toBe('pt-PT')
    expect(localVoice([v('en-US', false)], 'en')).toBeUndefined()
  })
})
