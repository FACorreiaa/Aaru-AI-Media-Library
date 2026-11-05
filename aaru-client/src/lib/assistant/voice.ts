import { SilenceDetector, levelOf } from './silence'

// ASK-009 on the web: a spoken question. The microphone records until a second and a half of
// quiet after speech (or a tap), in memory only; nothing is uploaded when no speech was heard.

export type Recording =
  { kind: 'audio'; blob: Blob; seconds: number } | { kind: 'noSpeech' }

export type Recorder = {
  /** Resolves once the recording ended, by silence, the cap, a tap or a cancel. */
  done: Promise<Recording>
  /** Ends now and keeps what was said. */
  stop: () => void
  /** Ends now and keeps nothing. */
  cancel: () => void
}

const STEP_MS = 100
const TYPES = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/ogg;codecs=opus']

/** Whether this browser can record a question at all. */
export function canRecord(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof MediaRecorder !== 'undefined' &&
    'mediaDevices' in navigator
  )
}

/** Starts recording. Rejects when the microphone is refused or missing. */
export async function startRecording(
  onLevel: (level: number) => void,
): Promise<Recorder> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
  const type = TYPES.find((t) => MediaRecorder.isTypeSupported(t))
  const recorder = new MediaRecorder(stream, type ? { mimeType: type } : {})
  const context = new AudioContext()
  const analyser = context.createAnalyser()
  analyser.fftSize = 2048
  context.createMediaStreamSource(stream).connect(analyser)
  const samples = new Float32Array(analyser.fftSize)
  const detector = new SilenceDetector()
  const chunks: Blob[] = []
  const startedAt = performance.now()
  let keep = true

  const done = new Promise<Recording>((resolve) => {
    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunks.push(event.data)
    }
    recorder.onstop = () => {
      clearInterval(timer)
      for (const track of stream.getTracks()) track.stop()
      void context.close().catch(() => undefined)
      const seconds = (performance.now() - startedAt) / 1000
      if (!keep || !detector.heardSpeech || chunks.length === 0)
        return resolve({ kind: 'noSpeech' })
      resolve({
        kind: 'audio',
        blob: new Blob(chunks, {
          type: recorder.mimeType || type || 'audio/webm',
        }),
        seconds,
      })
    }
  })
  const end = (kept: boolean) => {
    keep = kept
    if (recorder.state !== 'inactive') recorder.stop()
  }
  const timer = setInterval(() => {
    analyser.getFloatTimeDomainData(samples)
    const level = levelOf(samples)
    onLevel(level)
    const stop = detector.feed(level, (performance.now() - startedAt) / 1000)
    if (stop) end(stop !== 'noSpeech')
  }, STEP_MS)
  recorder.start()
  return { done, stop: () => end(true), cancel: () => end(false) }
}

/** What was said, read by the cluster's Whisper; its text and language. */
export async function transcribe(
  recording: Extract<Recording, { kind: 'audio' }>,
  fetchImpl: typeof fetch = fetch,
): Promise<{ text: string; language: string }> {
  let response: Response
  try {
    response = await fetchImpl('/app/assistant/voice', {
      method: 'POST',
      headers: {
        'Content-Type': recording.blob.type || 'audio/webm',
        'X-Audio-Seconds': recording.seconds.toFixed(1),
      },
      body: recording.blob,
    })
  } catch {
    throw new Error('Aaru could not reach the server. Try again in a moment.')
  }
  const json = (await response.json().catch(() => ({}))) as {
    text?: string
    language?: string
    code?: string
    message?: string
  }
  if (response.ok && json.text)
    return { text: json.text, language: json.language ?? '' }
  if (json.code === 'transcription_empty')
    throw new Error("I didn't catch that.")
  throw new Error(json.message ?? 'Aaru could not read that.')
}

const MUTE_KEY = 'aaru.assistant.muted'

/** Whether read-aloud is muted on this device. */
export function readAloudMuted(): boolean {
  try {
    return localStorage.getItem(MUTE_KEY) === '1'
  } catch {
    return false
  }
}

export function setReadAloudMuted(muted: boolean) {
  try {
    if (muted) localStorage.setItem(MUTE_KEY, '1')
    else localStorage.removeItem(MUTE_KEY)
  } catch {
    // Private mode: muted for this visit only.
  }
}

/**
 * Reads a reply aloud in the language the question was spoken in, only with a voice on this
 * device: some browsers' online voices send the text to their maker. No such voice, no reading.
 */
export function readAloud(text: string, language: string) {
  if (typeof speechSynthesis === 'undefined' || !text) return
  const voice = localVoice(speechSynthesis.getVoices(), language)
  if (!voice) return
  speechSynthesis.cancel()
  const utterance = new SpeechSynthesisUtterance(text)
  utterance.voice = voice
  utterance.lang = voice.lang
  speechSynthesis.speak(utterance)
}

/** An on-device voice for the language (its first part: `pt` takes `pt-PT`), else none. */
export function localVoice(
  voices: SpeechSynthesisVoice[],
  language: string,
): SpeechSynthesisVoice | undefined {
  const base = (language || navigatorLanguage()).toLowerCase().split('-')[0]
  const local = voices.filter((v) => v.localService)
  return (
    local.find(
      (v) => v.lang.toLowerCase().split('-')[0] === base && v.default,
    ) ?? local.find((v) => v.lang.toLowerCase().split('-')[0] === base)
  )
}

function navigatorLanguage(): string {
  return typeof navigator === 'undefined' ? 'en' : navigator.language
}

export function stopReading() {
  if (typeof speechSynthesis !== 'undefined') speechSynthesis.cancel()
}
