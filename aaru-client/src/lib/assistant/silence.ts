// When a spoken question has ended, from the microphone's level (AaruCore's SilenceDetector, on
// the web). Pure and clock-free: the caller passes the time of each reading.

export type Stop = 'silence' | 'noSpeech' | 'cap'

export const TUNING = {
  /** Quiet after speech that ends the recording, in seconds. */
  silence: 1.5,
  /** Recording that ends with no speech heard; nothing is uploaded. */
  noSpeech: 8,
  /** Longest recording (the server refuses more than 60 s). */
  cap: 60,
  /** dB over the floor that counts as speech. */
  margin: 10,
  /** Until the level has varied by `margin`, a reading this loud counts as speech. */
  loud: -30,
  /** Readings at or below this are digital silence and never set the floor. */
  digitalSilence: -90,
} as const

export class SilenceDetector {
  heardSpeech = false
  private floor: number | null = null
  private peak: number | null = null
  private quietSince: number | null = null

  /** One reading in dBFS at `time` seconds since recording began. Null keeps recording. */
  feed(power: number, time: number): Stop | null {
    if (time >= TUNING.cap) return 'cap'
    let speaking = false
    if (power > TUNING.digitalSilence) {
      this.floor = Math.min(this.floor ?? power, power)
      this.peak = Math.max(this.peak ?? power, power)
      speaking = this.isSpeech(power)
    }
    if (speaking) {
      this.heardSpeech = true
      this.quietSince = null
    } else if (this.heardSpeech && this.quietSince === null) {
      this.quietSince = time
    }
    if (this.heardSpeech) {
      return this.quietSince !== null &&
        time - this.quietSince >= TUNING.silence
        ? 'silence'
        : null
    }
    return time >= TUNING.noSpeech ? 'noSpeech' : null
  }

  private isSpeech(power: number): boolean {
    if (this.floor === null || this.peak === null) return false
    if (power >= this.floor + TUNING.margin) return true
    const varied = this.peak - this.floor >= TUNING.margin
    return !varied && power >= TUNING.loud
  }
}

/** dBFS of a frame of samples in [-1, 1]. */
export function levelOf(samples: Float32Array): number {
  let sum = 0
  for (const sample of samples) sum += sample * sample
  const rms = Math.sqrt(sum / Math.max(1, samples.length))
  return rms > 0 ? 20 * Math.log10(rms) : -160
}

/** A reply's markdown as text a voice can read (AaruCore's SpokenText). */
export function spokenText(markdown: string): string {
  const steps: Array<[RegExp, string]> = [
    [/\[([^\]\n]+)\]\([^)\s]*\)/g, '$1'],
    [/https?:\/\/\S+/g, ''],
    [/^[ \t]*#{1,6}[ \t]+/gm, ''],
    [/^[ \t]*[-*+][ \t]+/gm, ''],
    [/\*\*(?=\S)(.+?)(?<=\S)\*\*/g, '$1'],
    [/(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])/g, '$1'],
    [/(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])/g, '$1'],
    [/`([^`\n]*)`/g, '$1'],
    [/[ \t]{2,}/g, ' '],
    [/[ \t]+$/gm, ''],
  ]
  let text = markdown
  for (const [pattern, template] of steps)
    text = text.replace(pattern, template)
  return text.trim()
}
