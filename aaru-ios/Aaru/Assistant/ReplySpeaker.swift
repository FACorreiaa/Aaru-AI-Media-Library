import AaruCore
import AVFoundation
import Foundation

/// Reads a reply aloud with the on-device voice. No speech API beyond AVSpeechSynthesizer.
@MainActor
final class ReplySpeaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// `language` is Whisper's as sent; the voice falls back to the device's.
    func speak(_ reply: String, language: String) {
        let text = SpokenText.plain(reply)
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        if let voice = Self.voice(for: SpeechLanguage.code(from: language)) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func voice(for code: String?) -> AVSpeechSynthesisVoice? {
        guard let code else { return nil }
        if let region = Locale.current.region?.identifier,
           let voice = AVSpeechSynthesisVoice(language: "\(code)-\(region)")
        {
            return voice
        }
        if let voice = AVSpeechSynthesisVoice(language: code) {
            return voice
        }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.lowercased().hasPrefix(code) }
    }

    fileprivate func finished() {
        guard !synthesizer.isSpeaking else { return }
        #if os(iOS)
            // A stale callback must not deactivate a session the recorder has since taken.
            guard AVAudioSession.sharedInstance().category == .playback else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

extension ReplySpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
